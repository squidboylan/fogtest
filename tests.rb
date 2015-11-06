require 'fog'
require 'json'

class DHTest
  def initialize
    @auth_username = ENV['OS_USERNAME']
    @auth_password = ENV['OS_PASSWORD']
    @auth_url = ENV['OS_AUTH_URL'].chomp("/v2.0")
    @project_name = ENV['OS_TENANT_NAME']
    @region_name = 'RegionOne'
    @instance_name = "fogtestinstance"
  end

  def show
    puts "auth_username = #{@auth_username}"
    puts "auth_password = #{@auth_password}"
    puts "auth_url = #{@auth_url}"
    puts "project_name = #{@project_name}"
    puts "region_name = #{@region_name}"
  end

  def test_all
    self.show
    self.connect

    image = self.get_images
    flavor = self.get_flavors
    self.get_servers
    self.get_security_groups

    image = self.get_image image['id']
    flavor = self.get_flavor flavor['id']
    sec_group = self.create_sec_group 'fogtest'
    server = self.create_server flavor, image, sec_group
    ip = self.get_ip
    self.assign_ip server, ip
    self.remove_ip server, ip
    v = self.create_volume 'fogtestvol2'
    self.attach_volume v, server
    server.reload
    self.detach_volume v, server
    self.delete_server server
    self.delete_sec_group sec_group.id
    self.destroy_ip ip
    self.delete_volume v
  end

  # Authenticates to keystone
  def connect
    puts "Authenticating to #{@auth_url}"
    @conn = Fog::Compute.new({
      :provider            => 'openstack',
      :openstack_auth_url  => @auth_url + '/v2.0/tokens',
      :openstack_username  => @auth_username,
      :openstack_tenant    => @project_name,
      :openstack_api_key   => @auth_password
    })
  end

  # Gets a list of images, prints them to the screen and returns the first one
  def get_images
    puts "Getting image list"
    images = @conn.list_images

    for image in images.body['images']
      puts image
    end

    return images.body['images'][0]
  end

  # Gets a list of flavors, prints them to the screen and returns the first one
  def get_flavors
    puts "Getting flavor list"
    flavors = @conn.list_flavors

    for flavor in flavors.body['flavors']
      puts flavor
    end

    return flavors.body['flavors'][0]
  end

  # Gets a list of servers, prints them to the screen and returns them
  def get_servers
    puts "Getting server list"
    servers = @conn.list_servers

    for server in servers.body['servers']
      puts server
    end

    return servers.body['servers']
  end

  # Gets a list of security groups, prints them to the screen and returns them
  def get_security_groups
    puts "Getting security group list"
    groups = @conn.list_security_groups

    for group in groups.body['security_groups']
      puts group['name']
    end

    return groups.body['security_groups']
  end

  # Get an image
  def get_image(image_id)
    puts "Getting image #{image_id}"
    image = @conn.images.get(image_id)
    return image
  end

  # Get a flavor
  def get_flavor(flavor_id)
    puts "Getting flavor #{flavor_id}"
    flavor = @conn.flavors.get(flavor_id)
    return flavor
  end

  # Create a security group and add a rule for port 22
  def create_sec_group(name)
    puts "Creating security group #{name}"
    @conn.create_security_group name, 'test group'

    # Get the security group you just created
    for security_group in @conn.security_groups.all
      if security_group.name == name
        test_security_group = security_group
        break
      end
    end

    # Add the rule for port 22
    puts "Creating security group rule for port 22"
    @conn.security_group_rules.create :ip_protocol => 'TCP', :from_port => 22, :to_port => 22, :parent_group_id => test_security_group.id
    return test_security_group
  end

  # Delete a security group
  def delete_sec_group(group_id)
    puts "Deleting security group #{group_id}"
    @conn.delete_security_group group_id
  end

  # Create a server and wait until it is ready
  def create_server flavor, image, security_group
    puts "Creating server #{@instance_name}"
    instance = @conn.servers.create :name => @instance_name,
      :flavor_ref => flavor.id,
      :image_ref => image.id,
      :security_groups => security_group

    until instance.ready?
      for server in @conn.servers
        if server.name == instance.name
          instance = server
          break
        end
      end
    end
    puts "Instance Ready"
    return instance
  end

  # Delete a server and wait for it to delete
  def delete_server instance
    puts "Deleting instance"
    if not instance.destroy
      Kernel.abort("Failed to destroy instance")
    end
    exists = true
    while exists
      exists = false
      for server in @conn.servers
        if server.name == instance.name
          exists = true
        end
      end
    end
  end

  # Get a floating IP
  def get_ip
    puts "Getting IP to attach to server"
    return @conn.addresses.create
  end

  # Assign a floating IP to an instance
  def assign_ip instance, ip
    puts "Attaching IP to server"
    instance.associate_address(ip.ip)
  end

  # Detach a floating IP from an instance
  def remove_ip instance, ip
    puts "Detaching IP from server"
    instance.disassociate_address(ip.ip)
  end

  # Destroys an ip address
  def destroy_ip ip
    ip.destroy
  end

  # Creates a 1G volume with the description "Fogtest volume" and returns it
  def create_volume name
    puts "Creating volume"
    @conn.create_volume name, 'Fogtest volume', 1
    for vol in self.list_volumes
      if vol.name == name
        return vol
      end
    end
  end

  # Lists volumes
  def list_volumes
    puts "Listing_volumes"
    return @conn.volumes.all
  end

  # Attaches a volume to an instance
  def attach_volume vol, instance
    puts "Attaching volume to instance"

    # Attach the volume
    instance.attach_volume vol.id, "/dev/vdb"

    # Wait for the volume to attach
    while 1
      puts "Waiting for the volume to attach"
      instance.reload
      for volume in instance.volumes
        if volume.name = vol.name
          return
        end
      end
    end
  end

  # Detach the volume from the instance
  def detach_volume vol, instance
    puts "Detaching volume from instance"
    return instance.detach_volume vol.id
  end

  # Destroy the volume
  def delete_volume vol
    puts "Destroying volume"
    vol.destroy
  end
end

t = DHTest.new
t.test_all

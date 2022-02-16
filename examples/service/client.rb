#!/usr/bin/env ruby

require "dbus"

bus = DBus::SessionBus.instance
service = bus.service("org.opensuse.Yast")

storage = service.object("/org/opensuse/Yast/Storage")
storage_objects = storage["org.freedesktop.DBus.ObjectManager"].GetManagedObjects.first

disks_path = storage_objects.keys.first
disks = service.object(disks_path)
disks_objects = disks["org.freedesktop.DBus.ObjectManager"].GetManagedObjects.first

sda_path = disks_objects.keys.first
sda = service.object(sda_path)

puts "disk: #{sda["org.opensuse.Yast.Storage.Disk"]["Name"]}"

# car[DBus::PROPERTY_INTERFACE].on_signal("PropertiesChanged") do |iface, attrs, invalid_attrs|
#   require "byebug"; byebug
# end

# loop do
#   running = car["org.opensuse.Test.Car1"]["Running"]

#   foo = car["org.opensuse.Test.Car1"]["Foo"]

#   puts "Is the car running? #{running}, #{foo}"

#   sleep(0.5)

#   car["org.opensuse.Test.Car1"]["Running"] = 1
#   car["org.opensuse.Test.Car1"]["Foo"] = true
# end

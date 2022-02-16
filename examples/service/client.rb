#!/usr/bin/env ruby

require "dbus"

bus = DBus::SessionBus.instance
service = bus.service("org.opensuse.Test")

# car = service.object("/org/opensuse/Test/Car1")
# car.default_iface = "org.opensuse.Test.Car1"

manager = service.object("/org/opensuse/Test/Manager")
require "byebug"; byebug
objects = manager["org.freedesktop.DBus.ObjectManager"].GetManagedObjects


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

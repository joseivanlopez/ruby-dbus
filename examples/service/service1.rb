#!/usr/bin/env ruby

require "dbus"
Thread.abort_on_exception = true

module Test
  module DBus
    class Service
      attr_reader :bus

      def initialize
        @bus = ::DBus::SessionBus.instance
      end

      def export
        service = bus.request_service("org.opensuse.Test")
        manager = Manager.new("/org/opensuse/Test/Manager")
        manager.export(service)
      end

      def dispatch
        bus.dispatch_message_queue
      end
    end

    class Manager < ::DBus::Object
      def export(service)
        service.export(self)
        service.export(car_a)
        service.export(car_b)
      end

      def car_a
        @car_a ||= Car.new("/org/opensuse/Test/Manager/CarA")
      end

      def car_b
        @car_b ||= Car.new("/org/opensuse/Test/Manager/CarB")
      end

      dbus_interface "org.freedesktop.DBus.ObjectManager" do
        dbus_method :GetManagedObjects, "out objects:a{oa{sa{sv}}}" do
          [
            {
              car_a.path => [
                {
                  "org.opensuse.Test.Car1" => [
                    { "Running" => car_a.running }
                  ]
                }
              ]
            },
            {
              car_a.path => [
                {
                  "org.opensuse.Test.Car1" => [
                    { "Running" => car_a.running }
                  ]
                }
              ]
            }
          ]
        end
      end
    end

    class Car < ::DBus::Object
      attr_reader :instance

      def initialize(path)
        super

        @instance = ::Car.new
        @foo = false
      end

      def running=(value)
        instance.status = (value == 1) ? :on : :off
      end

      def running
        instance.running? ? 1 : 0
      end

      dbus_interface "org.opensuse.Test.Car1" do
        dbus_accessor :running, "u"
        dbus_attr_accessor :foo, "b"
      end
    end
  end
end

class Car
  attr_accessor :color
  attr_accessor :status

  def initialize
    @status = :off
  end

  def running?
    status == :on
  end
end

puts "listening"

service = Test::DBus::Service.new
service.export

loop do
  service.dispatch
  sleep(0.1)
end

#!/usr/bin/env ruby

require "dbus"
Thread.abort_on_exception = true

module Yast
  module DBus
    class Service
      attr_reader :bus

      def initialize
        @bus = ::DBus::SessionBus.instance
      end

      def export
        storage.export
      end

      def dispatch
        bus.dispatch_message_queue
      end

      def storage
        @storage ||= Storage.new(self, "/org/opensuse/Yast/Storage")
      end

      def dbus_service
        @dbus_service ||= bus.request_service("org.opensuse.Yast")
      end
    end

    class Storage < ::DBus::Object
      attr_reader :yast_service

      def initialize(service, path)
        super(path)

        @yast_service = service
      end

      def export
        yast_service.dbus_service.export(self)
        disks.export
      end

      def disks
        @disks ||= Disks.new(yast_service, "/org/opensuse/Yast/Storage/Disks")
      end

      dbus_interface "org.freedesktop.DBus.ObjectManager" do
        dbus_method :GetManagedObjects, "out objects:a{sa{sa{sv}}}" do
          objects = {
            disks.path => {
              "org.freedesktop.DBus.ObjectManager" => {}
            }
          }

          [objects]
        end
      end
    end

    class Disks < ::DBus::Object
      attr_reader :yast_service

      def initialize(service, path)
        super(path)

        @yast_service = service
      end

      def export
        yast_service.dbus_service.export(self)
        disks.each(&:export)
      end

      def disks
        @disks ||= storage_disks.map { |d| Disk.new(yast_service, d) }
      end

      def storage_disks
        [
          Yast::Disk.new("/dev/sda"),
          Yast::Disk.new("/dev/sdb")
        ]
      end

      dbus_interface "org.freedesktop.DBus.ObjectManager" do
        dbus_method :GetManagedObjects, "out objects:a{sa{sa{sv}}}" do
          objects = disks.inject({}) { |h, d| h.merge(d.interfaces_attributes) }

          [objects]
        end
      end
    end

    class Disk < ::DBus::Object
      attr_reader :yast_service

      attr_reader :storage_disk

      def initialize(service, disk)
        @yast_service = service
        @storage_disk = disk

        name = disk.name.split("/").last.capitalize
        path = "/org/opensuse/Yast/Storage/Disks/#{name}"

        super(path)
      end

      def export
        yast_service.dbus_service.export(self)
      end

      def interfaces_attributes
        {
          path => {
            "org.opensuse.Yast.Storage.Disk" => {
              "Name" => name
            }
          }
        }
      end

      def name
        storage_disk.name
      end

      def name=(value)
        storage_disk.name = value
      end

      dbus_interface "org.opensuse.Yast.Storage.Disk" do
        dbus_accessor :name, "s"
      end
    end
  end

  class Disk
    attr_accessor :name

    def initialize(name)
      @name = name
    end
  end
end

puts "listening"

service = Yast::DBus::Service.new
service.export

loop do
  service.dispatch
  sleep(0.1)
end

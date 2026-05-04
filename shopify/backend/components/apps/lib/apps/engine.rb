module Apps
  class Engine < ::Rails::Engine
    isolate_namespace Apps
  end
end

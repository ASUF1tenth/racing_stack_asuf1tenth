#!/usr/bin/env python3
import sys
import os
import yaml
import rclpy
from ament_index_python.packages import get_package_share_directory

# Monkey-patch rclpy.spin_once to prevent indefinite blocking in wait_for_messages
original_spin_once = rclpy.spin_once

def patched_spin_once(node, *, executor=None, timeout_sec=None):
    if timeout_sec is None:
        timeout_sec = 0.1
    return original_spin_once(node, executor=executor, timeout_sec=timeout_sec)

rclpy.spin_once = patched_spin_once

# Import the original controller module
import controller.controller_manager as cm

# Store the original methods
original_init_ftg_controller = cm.Controller.init_ftg_controller
original_ftg_cycle = cm.Controller.ftg_cycle

# Define our patched method that loads l1_params
def patched_init_ftg_controller(self):
    # Load l1 parameters to satisfy constructor requirements
    stack_master_path = get_package_share_directory('stack_master')
    config_path = os.path.join(stack_master_path, 'config', self.racecar_version, 'l1_params.yaml')
    with open(config_path, 'r') as f:
        self.l1_params = yaml.safe_load(f)
        self.l1_params = self.l1_params['controller']['ros__parameters']
    
    # Call the original initialization
    original_init_ftg_controller(self)

# Define our patched ftg_cycle that checks if scan exists
def patched_ftg_cycle(self):
    if not hasattr(self, 'scan') or self.scan is None:
        if not hasattr(self, '_logged_scan_warning') or not self._logged_scan_warning:
            self.get_logger().warning("No LaserScan message received on /scan yet. Waiting...")
            self._logged_scan_warning = True
        return 0.0, 0.0
    self._logged_scan_warning = False
    return original_ftg_cycle(self)

# Apply the monkey patches
cm.Controller.init_ftg_controller = patched_init_ftg_controller
cm.Controller.ftg_cycle = patched_ftg_cycle

def main(args=None):
    # Execute the original main loop
    cm.main()

if __name__ == '__main__':
    main()

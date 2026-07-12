#!/usr/bin/env python3
import rclpy

# Monkey-patch rclpy.spin_once to prevent indefinite blocking in the constructor
original_spin_once = rclpy.spin_once

def patched_spin_once(node, *, executor=None, timeout_sec=None):
    # If timeout_sec is not specified (None), default to 0.1s to allow periodic
    # wake-ups and rebuild the DDS wait sets during discovery
    if timeout_sec is None:
        timeout_sec = 0.1
    return original_spin_once(node, executor=executor, timeout_sec=timeout_sec)

rclpy.spin_once = patched_spin_once

# Import StateMachine and apply monkey-patch to bypass ot_interpolator service check
from state_machine.state_machine import StateMachine

def patched_init_ot_params(self):
    self.get_logger().info("Patched init_ot_params: Bypassing ot_interpolator parameter check for FTG.")
    self.n_ot_sectors = 0
    self.ot_param_names = []
    self.ot_sectors = []
    from rclpy.parameter_event_handler import ParameterEventHandler
    self.handler = ParameterEventHandler(self)

StateMachine.init_ot_params = patched_init_ot_params

# Monkey-patch glb_wpnts_scaled_cb to trace incoming message size
original_glb_wpnts_scaled_cb = StateMachine.glb_wpnts_scaled_cb

def patched_glb_wpnts_scaled_cb(self, data):
    self.get_logger().info(f"Patched scaled_cb: Received scaled waypoints with {len(data.wpnts)} points.")
    original_glb_wpnts_scaled_cb(self, data)

StateMachine.glb_wpnts_scaled_cb = patched_glb_wpnts_scaled_cb

# Import and run the main entry point
from state_machine.state_machine import main

if __name__ == '__main__':
    main()

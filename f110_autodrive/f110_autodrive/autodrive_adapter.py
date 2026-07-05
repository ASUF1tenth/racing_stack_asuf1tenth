#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from sensor_msgs.msg import LaserScan, Imu
from nav_msgs.msg import Odometry
from ackermann_msgs.msg import AckermannDriveStamped
from std_msgs.msg import Float32


class F110AutoDriveAdapter(Node):
    def __init__(self):
        super().__init__('autodrive_adapter')

        # Declare parameters
        self.declare_parameter('max_steer_rad', 0.4189)  # ~24 degrees
        self.declare_parameter('Kff_lin', 0.04)
        self.declare_parameter('Kff_quad', 0.000139)

        self.max_steer_rad = self.get_parameter('max_steer_rad').value
        self.Kff_lin = self.get_parameter('Kff_lin').value
        self.Kff_quad = self.get_parameter('Kff_quad').value

        self.current_speed = 0.0

        # Subscriptions from AutoDRIVE
        self.lidar_sub = self.create_subscription(
            LaserScan,
            '/autodrive/roboracer_1/lidar',
            self.lidar_callback,
            10
        )
        self.odom_sub = self.create_subscription(
            Odometry,
            '/autodrive/roboracer_1/odom',
            self.odom_callback,
            10
        )
        self.imu_sub = self.create_subscription(
            Imu,
            '/autodrive/roboracer_1/imu',
            self.imu_callback,
            10
        )

        # Subscription from Autonomy Stack
        self.drive_sub = self.create_subscription(
            AckermannDriveStamped,
            '/drive',
            self.drive_callback,
            10
        )

        # Publishers to Autonomy Stack
        self.scan_pub = self.create_publisher(LaserScan, '/scan', 10)
        self.odom_pub = self.create_publisher(Odometry, '/odom', 10)
        self.imu_pub_ekf = self.create_publisher(Imu, '/sensors/imu/raw', 10)
        self.imu_pub_ctrl = self.create_publisher(Imu, '/vesc/sensors/imu/raw', 10)

        # Publishers to AutoDRIVE
        self.steer_pub = self.create_publisher(Float32, '/autodrive/roboracer_1/steering_command', 10)
        self.throttle_pub = self.create_publisher(Float32, '/autodrive/roboracer_1/throttle_command', 10)

        self.last_drive_time = self.get_clock().now()
        self.in_timeout = True
        self.watchdog_timer = self.create_timer(0.1, self.watchdog_callback)

        self.get_logger().info('F1Tenth AutoDRIVE Adapter Node Initialized')

    def lidar_callback(self, msg: LaserScan):
        # Forward LiDAR scan with frame_id remapped to 'laser'
        msg.header.frame_id = 'laser'
        self.scan_pub.publish(msg)

    def odom_callback(self, msg: Odometry):
        # Update current speed for the longitudinal controller
        self.current_speed = msg.twist.twist.linear.x

        # Forward Odometry with frames remapped to match EKF expectations
        msg.header.frame_id = 'odom'
        msg.child_frame_id = 'base_link'
        self.odom_pub.publish(msg)

    def imu_callback(self, msg: Imu):
        # Forward IMU data with frame_id remapped to 'imu'
        msg.header.frame_id = 'imu'
        self.imu_pub_ekf.publish(msg)
        self.imu_pub_ctrl.publish(msg)

    def drive_callback(self, msg: AckermannDriveStamped):
        self.last_drive_time = self.get_clock().now()
        if self.in_timeout:
            self.get_logger().info('Drive commands received. Control active.')
            self.in_timeout = False
        target_speed = msg.drive.speed
        target_steering_angle = msg.drive.steering_angle

        # 1. Normalize steering command: map to [-1, 1]
        u_steer = target_steering_angle / self.max_steer_rad
        u_steer = max(-1.0, min(1.0, u_steer))

        # 2. Compute throttle command using quadratic feedforward control (non-negative clamping)
        if target_speed <= 0.01:
            u_throttle = 0.0
        else:
            u_throttle = (self.Kff_quad * (target_speed ** 2)) + (self.Kff_lin * target_speed)
            u_throttle = max(0.0, min(1.0, u_throttle))

        # Publish normalized commands to AutoDRIVE
        steer_msg = Float32()
        steer_msg.data = float(u_steer)
        self.steer_pub.publish(steer_msg)

        throttle_msg = Float32()
        throttle_msg.data = float(u_throttle)
        self.throttle_pub.publish(throttle_msg)

    def watchdog_callback(self):
        time_since_last_drive = (self.get_clock().now() - self.last_drive_time).nanoseconds / 1e9
        if time_since_last_drive > 0.2:
            # Publish safe 0.0 commands (straight wheels, active braking)
            steer_msg = Float32()
            steer_msg.data = 0.0
            self.steer_pub.publish(steer_msg)

            throttle_msg = Float32()
            throttle_msg.data = 0.0
            self.throttle_pub.publish(throttle_msg)

            if not self.in_timeout:
                self.get_logger().warn('Watchdog timeout: Lost connection to drive commands. Halting vehicle!')
                self.in_timeout = True


def main(args=None):
    rclpy.init(args=args)
    node = F110AutoDriveAdapter()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == '__main__':
    main()

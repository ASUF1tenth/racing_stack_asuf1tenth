#!/usr/bin/env python3
import rclpy
from rclpy.node import Node
from nav_msgs.msg import Odometry
from geometry_msgs.msg import PoseStamped
from f110_msgs.msg import WpntArray, Wpnt

class DummyPublisher(Node):
    def __init__(self):
        super().__init__('dummy_publisher')
        
        # Publishers
        self.global_wp_pub = self.create_publisher(WpntArray, '/global_waypoints', 10)
        self.local_wp_pub = self.create_publisher(WpntArray, '/local_waypoints', 10)
        self.scaled_wp_pub = self.create_publisher(WpntArray, '/global_waypoints_scaled', 10)
        self.odom_pub = self.create_publisher(Odometry, '/car_state/odom', 10)
        self.pose_pub = self.create_publisher(PoseStamped, '/car_state/pose', 10)
        self.frenet_pub = self.create_publisher(Odometry, '/car_state/frenet/odom', 10)

        # Timer to publish at 10Hz
        self.timer = self.create_timer(0.1, self.timer_callback)
        self.get_logger().info('F1Tenth Dummy Publisher Node Initialized')

    def timer_callback(self):
        now = self.get_clock().now().to_msg()

        # 1. Create a dummy WpntArray with at least 2 elements (required by CubicSpline interpolation)
        wpnt_array = WpntArray()
        wpnt_array.header.stamp = now
        wpnt_array.header.frame_id = 'map'
        
        # Waypoint 1
        dummy_wpnt1 = Wpnt()
        dummy_wpnt1.id = 0
        dummy_wpnt1.s_m = 0.0
        dummy_wpnt1.d_m = 0.0
        dummy_wpnt1.x_m = 0.0
        dummy_wpnt1.y_m = 0.0
        dummy_wpnt1.d_right = 1.5
        dummy_wpnt1.d_left = 1.5
        dummy_wpnt1.psi_rad = 0.0
        dummy_wpnt1.kappa_radpm = 0.0
        dummy_wpnt1.vx_mps = 1.5
        dummy_wpnt1.ax_mps2 = 0.0
        wpnt_array.wpnts.append(dummy_wpnt1)

        # Waypoint 2
        dummy_wpnt2 = Wpnt()
        dummy_wpnt2.id = 1
        dummy_wpnt2.s_m = 50.0
        dummy_wpnt2.d_m = 0.0
        dummy_wpnt2.x_m = 50.0
        dummy_wpnt2.y_m = 0.0
        dummy_wpnt2.d_right = 1.5
        dummy_wpnt2.d_left = 1.5
        dummy_wpnt2.psi_rad = 0.0
        dummy_wpnt2.kappa_radpm = 0.0
        dummy_wpnt2.vx_mps = 1.5
        dummy_wpnt2.ax_mps2 = 0.0
        wpnt_array.wpnts.append(dummy_wpnt2)

        # Waypoint 3
        dummy_wpnt3 = Wpnt()
        dummy_wpnt3.id = 2
        dummy_wpnt3.s_m = 100.0
        dummy_wpnt3.d_m = 0.0
        dummy_wpnt3.x_m = 100.0
        dummy_wpnt3.y_m = 0.0
        dummy_wpnt3.d_right = 1.5
        dummy_wpnt3.d_left = 1.5
        dummy_wpnt3.psi_rad = 0.0
        dummy_wpnt3.kappa_radpm = 0.0
        dummy_wpnt3.vx_mps = 1.5
        dummy_wpnt3.ax_mps2 = 0.0
        wpnt_array.wpnts.append(dummy_wpnt3)

        # Publish waypoints
        self.global_wp_pub.publish(wpnt_array)
        self.local_wp_pub.publish(wpnt_array)
        self.scaled_wp_pub.publish(wpnt_array)

        # 2. Create a dummy Odometry message for car_state/odom
        odom_msg = Odometry()
        odom_msg.header.stamp = now
        odom_msg.header.frame_id = 'odom'
        odom_msg.child_frame_id = 'base_link'
        # Zero position and velocity
        odom_msg.pose.pose.position.x = 0.0
        odom_msg.pose.pose.position.y = 0.0
        odom_msg.twist.twist.linear.x = 0.0
        
        self.odom_pub.publish(odom_msg)
        self.frenet_pub.publish(odom_msg)

        # 3. Create a dummy PoseStamped message for car_state/pose
        pose_msg = PoseStamped()
        pose_msg.header.stamp = now
        pose_msg.header.frame_id = 'map'
        pose_msg.pose.position.x = 0.0
        pose_msg.pose.position.y = 0.0
        pose_msg.pose.orientation.w = 1.0
        
        self.pose_pub.publish(pose_msg)

def main(args=None):
    rclpy.init(args=args)
    node = DummyPublisher()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.destroy_node()
        rclpy.shutdown()

if __name__ == '__main__':
    main()

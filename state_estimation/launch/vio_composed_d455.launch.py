# -----------------------------------------------------------------------------
# Refactored for RealSense D455 + Racecar Stack EKF
# Based on the component layout by Bernd Pfrommer <bernd.pfrommer@gmail.com>
# -----------------------------------------------------------------------------

import launch
from launch.substitutions import LaunchConfiguration as LaunchConfig
from launch.substitutions import PathJoinSubstitution
from launch.actions import DeclareLaunchArgument as LaunchArg
from launch.actions import OpaqueFunction
from launch_ros.substitutions import FindPackageShare
from launch_ros.actions import ComposableNodeContainer, Node
from launch_ros.descriptions import ComposableNode


def pkg_file(fname):
    return PathJoinSubstitution(
        [FindPackageShare('state_estimation'), 'config', fname])


def launch_setup(context, *args, **kwargs):
    """Dynamically set up parameters and assemble the component container."""
    
    # 1. Evaluate the racecar version string to dynamically resolve the calibration file
    racecar_version = LaunchConfig('racecar_version').perform(context)
    calib_file_name = f"d455_calib_{racecar_version}.json"
    config_file_name = "d455_vio_config.json"

    # 2. Re-map arguments to fit the VIO parameters
    common_parameters = {
        'calibration_file': pkg_file(calib_file_name),
        'vio_config_file': pkg_file(config_file_name)
    }
    
    frontend_parameters = common_parameters
    backend_parameters = {
        **common_parameters,
        'world_frame_id': 'odom',                  # REP-105: VIO outputs to drifting odom frame
        'child_frame_id': LaunchConfig('imu_frame'),
        'publish_tf': False,                       # Let EKF handle global transform publishing
        'has_split_accel_and_gyro_topics': False   # D455 outputs a unified combined IMU topic
    }

    # 3. Port your exact topic configurations into remappings
    frontend_remappings = [
        ('left_image', LaunchConfig('left_image_topic')),
        ('right_image', LaunchConfig('right_image_topic'))
    ]
    
    backend_remappings = [
        ('optical_flow', 'optical_flow'),          # Intra-process link between front/back end
        ('imu', LaunchConfig('imu_topic')),
        ('odom', '/basalt/odomimu')                # Intermediate topic fed to the EKF bridge
    ]

    # 4. Define the high-performance component container
    container = ComposableNodeContainer(
        name='basalt_vio_container',
        namespace='basalt',
        package='rclcpp_components',
        executable='component_container',
        composable_node_descriptions=[
            ComposableNode(
                package='basalt_ros',
                plugin='basalt_ros::VIOFrontEndNode',
                name='vio_frontend',
                namespace='basalt',
                parameters=[frontend_parameters],
                remappings=frontend_remappings,
                extra_arguments=[{'use_intra_process_comms': True}],
            ),
            ComposableNode(
                package='basalt_ros',
                plugin='basalt_ros::VIOBackEndNode',
                name='vio_backend',
                namespace='basalt',
                parameters=[backend_parameters],
                remappings=backend_remappings,
                extra_arguments=[{'use_intra_process_comms': True}],
            ),
        ],
        output='screen'
    )

    # 5. Bridge Node: Handles frame rotation and lever-arm corrections for robot_localization
    basalt_to_ekf_node = Node(
        package='state_estimation',
        executable='basalt_to_ekf_node',
        name='basalt_to_ekf',
        output='screen',
        parameters=[{
            'input_topic': '/basalt/odomimu',
            'output_topic': LaunchConfig('odom_topic'),
            'imu_frame': LaunchConfig('imu_frame'),
            'imu_topic': LaunchConfig('imu_topic'),
            'tf_timeout': LaunchConfig('tf_timeout')
        }]
    )

    # Return both targets to be executed simultaneously
    return [container, basalt_to_ekf_node]


def generate_launch_description():
    """Declare the user arguments and execute the opaque setup logic."""
    return launch.LaunchDescription([
        LaunchArg('racecar_version',
                  default_value='NUC6',
                  description='Selects config/d455_calib_<racecar_version>.json'),
        LaunchArg('left_image_topic',
                  default_value='/camera/infra1/image_rect_raw',
                  description='Left infra camera raw image topic'),
        LaunchArg('right_image_topic',
                  default_value='/camera/infra2/image_rect_raw',
                  description='Right infra camera raw image topic'),
        LaunchArg('imu_topic',
                  default_value='/camera/imu',
                  description='Combined RealSense IMU data topic'),
        LaunchArg('imu_frame',
                  default_value='camera_imu',
                  description='Basalt body frame identity'),
        LaunchArg('odom_topic',
                  default_value='/basalt/odom',
                  description='EKF-ready target destination odometry topic'),
        LaunchArg('tf_timeout',
                  default_value='30.0',
                  description='Seconds the bridge node yields for driver transforms to wake up'),
        OpaqueFunction(function=launch_setup)
    ])
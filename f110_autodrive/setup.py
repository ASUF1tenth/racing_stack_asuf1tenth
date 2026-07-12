from setuptools import setup
import os
from glob import glob

package_name = 'f110_autodrive'

setup(
    name=package_name,
    version='0.0.1',
    packages=[package_name],
    data_files=[
        ('share/ament_index/resource_index/packages',
            ['resource/' + package_name]),
        ('share/' + package_name, ['package.xml']),
        (os.path.join('share', package_name, 'launch'), glob('launch/*.xml')),
    ],
    install_requires=['setuptools'],
    zip_safe=True,
    maintainer='mohany',
    maintainer_email='mohany@tuf.local',
    description='AutoDRIVE simulator adapter for the F1Tenth modular stack',
    license='MIT',
    tests_require=['pytest'],
    entry_points={
        'console_scripts': [
            'autodrive_adapter = f110_autodrive.autodrive_adapter:main',
            'dummy_publisher = f110_autodrive.dummy_publisher:main',
            'autodrive_controller = f110_autodrive.autodrive_controller_wrapper:main',
            'autodrive_state_machine = f110_autodrive.autodrive_state_machine_wrapper:main',
        ],
    },
)

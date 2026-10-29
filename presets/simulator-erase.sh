PRESET_NAME="simulator-erase"
PRESET_DESC="Reset picked simulators to factory state (keeps the device, drops its apps and data)"
PRESET_SAFE=false
PRESET_INTERACTIVE=true
PRESET_SIZE_PATHS=("$HOME/Library/Developer/CoreSimulator/Devices")
PRESET_COMMAND='_sim_pick_devices erase'

# wledMatrixHelper
A quick power shell script to send text objects and timers to a WLED instance on the local network. 


WLED Scroller - Command Line Help

Usage:
  .\wledscroller.ps1 [options]

Options:
  -message         "Text to scroll"
  -fg              "R,G,B" foreground color
  -bg              "R,G,B" background color
  -speed           Scroll speed (0-255)
  -config          Path to config file (default: wledscroller.json)
  -manualMin       Manual counter minimum
  -manualMax       Manual counter maximum
  -manualOrange    Manual green->orange threshold
  -manualRed       Manual orange->red threshold
  -autoMin         Auto counter minimum
  -autoMax         Auto counter maximum
  -autoOrange      Auto green->orange threshold
  -autoRed         Auto orange->red threshold
  -h, --help       Show this help screen

Examples:
  .\wledscroller.ps1 -message "Watt Up" -fg "255,0,0" -speed 150
  .\wledscroller.ps1 -config ".\myconfig.json"

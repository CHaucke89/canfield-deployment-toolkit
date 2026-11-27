# Files loaded by Install-Toolkit.ps1, in order (paths relative to src\).
# Build-Toolkit-Exe.ps1 reads this same list to inline the files into the single-file exe.
# Sidebar order follows the order of the tabs\ entries; ui\Shell.ps1 comes after them.
@(
    'lib\Log.ps1'
    'lib\Validation.ps1'
    'lib\Sponsors.ps1'
    'lib\Usb.ps1'
    'lib\CaptureCleanup.ps1'
    'lib\Users.ps1'
    'lib\Status.ps1'
    'ui\MainWindow.ps1'
    'ui\Progress.ps1'
    'ui\Theme.ps1'
    'tabs\Computer.ps1'
    'tabs\RemoteAccess.ps1'
    'tabs\CanfieldCapture.ps1'
    'tabs\Users.ps1'
    'tabs\CleanupTool.ps1'
    'tabs\Summary.ps1'
    'tabs\Scripts.ps1'
    'ui\Shell.ps1'
)

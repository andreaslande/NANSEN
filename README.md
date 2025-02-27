# NANSEN - Neuro ANalysis Software ENsemble

A collection of apps and modules for processing, analysis and visualization 
of two-photon imaging data for the systems neuroscience community.


## Installation
Currently, the only actions that are needed is:
 1) Clone the repository and add all subfolders to MATLAB's search path. 
 2) Make sure the dependencies listed below are installed

Note: As more modules and toolboxes are added in the next weeks and months, 
these lists will get updated.

### Required Matlab toolboxes
 - Image Processing Toolbox
 - Statistics and Machine Learning Toolbox
 - Parallel Computing Toolbox

To check if these toolboxes are already installed, use the `ver` command. 
Typing `ver` in matlab's command window will display all installed toolboxes. 
If any of the above toolboxes are not installed, they can be installed by 
navigating to MATLAB's Home tab and then selecting Add-Ons > Get Add-Ons

### Other toolboxes
 - GUI Layout Toolbox ([View toolbox site](https://se.mathworks.com/matlabcentral/fileexchange/66235-widgets-toolbox-compatibility-support?s_tid=srchtitle))
 - Widgets Toolbox ([Download toolbox installer](https://se.mathworks.com/matlabcentral/mlc-downloads/downloads/b0bebf59-856a-4068-9d9c-0ed8968ac9e6/099f0a4d-9837-4e5f-b3df-aa7d4ec9c9c9/packages/mltbx) | [View toolbox site](https://se.mathworks.com/matlabcentral/fileexchange/66235-widgets-toolbox-compatibility-support?s_tid=srchtitle))


These toolboxes can also be installed using MATLAB's addon manager, but it 
is important to install a compatibility version (v1.3.330) of the Widgets Toolbox, 
so please use the download link above.

## Apps

### Imviewer
App for viewing and interacting with videos & image stacks

<img src="https://ehennestad.github.io/images/imviewer.png" alt="Imviewer instance" width="500"/>

### Fovmanager
App for registering cranial implants, injection spots and imaging field of views (and RoIs) on an atlas of the dorsal surface of the cortex.

<img src="https://ehennestad.github.io/images/fovmanager.png" alt="Imviewer instance" width="500"/>


#  Title

Sequential 2.2.0 (2022-11-05).

This is a modernized build of Sequential for Intel and Apple Silicon Macs
running 10.14 (Intel) or 11.4 (Apple Silicon) or later.

The last build came out in 2010 so this program needed some work to get it
working for modern Macs.

The codebase (and its dependencies) have been updated to build with Xcode
13.2. Sequential is now built as an Universal app and has been tested on
macOS 10.14 (on an Intel Mac) and macOS 11.7.1 (on an Apple Silicon Mac).









Building instructions

- decompress the source archive into a folder
  - dependencies are included in the source archive
- open the Sequential folder inside the chosen folder
- open the Sequential.xcodeproj project in Xcode
- select the Sequential build scheme
- the use Product -> Build command





Distribution instructions

- update the History file

- to create the source backup archive:

% cd ~/folder_containing_sequential_sources
% tar -c -v -J -H -f Sequential_all.tar.xz --exclude=xcuserdata --exclude=.DS_Store Sequential XADMaster UniversalDetector

- to distribute the built app:

[1] select Product -> Archive in Xcode then copy the archive to a staging folder, eg,
    ~/Sequential_staging
[2] build a compressed tar of the .app bundle for embedding inside a .rtfd bundle.
    NB: the 'cd' is required otherwise the tar will contain parent-paths.
    For example:

% cd ~/Sequential_staging/Sequential\ 2021-08-04\ 15.27.00.xcarchive/Products/Applications
% tar -c -v -J -f ../../../Sequential\ 2021-08-04\ 15.27.00.tar.xz Sequential.app
% cd ~

[3] copy the "Sequential RTFD template" file from the distribution folder (inside
    the "Sequential" source folder) to the staging folder

[4] open the copied RTFD file and embed the .tar.xz file inside it by:
    [A] selecting the <replace me> text and deleting the text
    [B] drag and drop the .tar.xz file from the Finder to where the <replace me>
        text was
	[C] save and close the RTFD file

[5] rename the .rtfd file - it's best to embed the release date/time into
    the file name so the user will know which version it is

[6] create a zip archive containing just the RTFD file
 
[7] upload or distribute the .zip file

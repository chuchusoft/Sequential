# Sequential 2.6.0 (2024-09-07).

Sequential is an image and comic viewer for macOS. It can display images
in folders, PDF files, and archives of these formats: ZIP CBZ RAR CBR 7z.

This is a modernized build of Sequential for Intel and Apple Silicon Macs
running 10.14 (Intel) or 11.4 (Apple Silicon) or later.

This version contains bug fixes and some feature improvements such as the
ability to go to a specific page number, the ability to invert the
colors displayed (useful for reading text-based PDF documents in Dark
Mode), and the ability to reset the displayed image's free rotation.

To see the release notes for this version, please read the
[History](History.txt) file.

There will probably not be any further changes or improvements to this
program because of limited free time and no strong desire to improve the
program any further.

There are parts of the application which probably won’t work properly
(HTML URLs may not display correctly) and it may have bugs and crashes.
Caveat emptor. For folders, PDFs and archives, the application works well.

The codebase (and its dependencies) have been updated to build with Xcode
14.2. Sequential is now built as an Universal app and has been tested on
macOS 10.14.5 (on an Intel Mac) and macOS 12.7.6 (on an Apple Silicon Mac).




## Source code

The modernized Sequential source code is at <https://github.com/chuchusoft/Sequential>.

The original Sequential source code is at <https://github.com/btrask/Sequential>.





## Building instructions

- decompress the source archive into a folder
  - dependencies are included in the source archive
- open the Sequential folder inside the chosen folder
- open the Sequential.xcodeproj project in Xcode
- select the Sequential build scheme
- use the Product -> Build command





## Distribution instructions

- update the History file

- to create the source backup archive:

% cd ~/folder_containing_sequential_sources
% tar -c -v -J -H -f Sequential.src.2021-08-04.15.27.00.tar.xz --exclude=xcuserdata --exclude=.DS_Store --exclude=.git  --exclude=.gitignore --exclude=.gitattributes --exclude=Sequential/docs --exclude=XADMaster/Windows Sequential XADMaster UniversalDetector

- to distribute the built app:

[1] select Product -> Archive in Xcode then copy the archive to a staging folder, eg,
    ~/Sequential_staging

[2] move the .app bundle to the staging folder:

% mv ~/Sequential_staging/Sequential\ 2021-08-04\ 15.27.00.xcarchive/Products/Applications ~/Sequential_staging

[3] copy the "HOWTO remove the Sequential application from quarantine.rtfd" and
    "Remove quarantine attribute.applescript" files from the distribution folder
    (inside the "Sequential" source folder) to the staging folder

[4] remove Finder .DS_Store files:

% find ~/Sequential_staging -name .DS_Store -exec rm -- {} +

[5] rename the staging folder to include the release date/time:

% mv ~/Sequential_staging ~/Sequential\ 2021-08-04\ 15.27.00

[6] create an archive of the renamed staging folder:

% tar -c -v -J -H -f ~/Sequential.app.2021-08-04.15.27.00.tar.xz ~/Sequential\ 2021-08-04\ 15.27.00
 
[7] upload or distribute the .tar.xz files (app and src)

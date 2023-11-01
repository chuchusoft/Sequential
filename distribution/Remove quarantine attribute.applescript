(*
	Removes the quarantine atttribute (xattr) from each item dropped onto this application.

	In general, application bundles should be dropped. There is no point in dropping documents.

	Warning: do not drop disks onto this app; the disk's contents will take a long time to
	process and this app cannot be easily stopped.

	After removing the quarantine xattr, the application can be opened even if it is not notarized.

	This file is released as part of the Sequential app's distribution.

	Created 2023/11/01.
	Licensed under the terms of the "unlicense" license <https://unlicense.org>.
 *)

on open filelist
	repeat with i in filelist
		do shell script "xattr -d com.apple.quarantine -r '" & POSIX path of i & "'"
	end repeat
	
	if 1 = (count of filelist) then
		set p1 to POSIX path of item 1 of filelist
		set n1 to (do shell script "basename '" & p1 & "'")
		display dialog "The quarantine attribute of " & n1 & " was removed." buttons {"Quit"} Â
			default button 1 with title "No Longer Quarantined"
	else
		display dialog "The quarantine attribute was removed from " & (count of filelist) & " items." buttons {"Quit"} Â
			default button 1 with title "No Longer Quarantined"
	end if
end open
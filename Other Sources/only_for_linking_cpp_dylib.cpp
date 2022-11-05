//
//  only_for_linking_cpp_dylib.cpp
//  Sequential
//
//  Created by Vincent Tan on 2021/08/04.
//

//	Problem: when the UniversalDetector library is statically
//	linked to the Sequential app, the standard C++ dynamic
//	library libc++ is not linked against by the linker because
//	no code in Sequential uses C++ (only Objective-C is used)
//	which then results in the libc++ symbols being reported as
//	missing and the linker then fails to generate an executable
//	for the .app bundle.

//	Solution: build with an empty C++ source file. This will
//	trigger Xcode's build system to link against the libc++ dylib.

//#include <stdio.h>

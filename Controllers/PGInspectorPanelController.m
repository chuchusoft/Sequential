/* Copyright © 2007-2009, The Sequential Project
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of the the Sequential Project nor the
      names of its contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE SEQUENTIAL PROJECT ''AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE SEQUENTIAL PROJECT BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. */
#import "PGInspectorPanelController.h"

// Models
#import "PGNode.h"
#import "PGResourceAdapter.h"

// Controllers
#import "PGDocumentController.h"
#import "PGDisplayController.h"

// Other Sources
#import "PGFoundationAdditions.h"
#import "PGGeometry.h"
#import "PGZooming.h"

@interface NSObject(PGAdditions)
- (id)PG_replacementUsingObject:(id)replacement preserveUnknown:(BOOL)preserve getTopLevelKey:(out id *)outKey;
@end

@interface NSDictionary(PGAdditions)
- (NSDictionary *)PG_flattenedDictionary;
@end

@interface PGInspectorPanelController(Private)
- (void)_updateColumnWidths;
- (NSDictionary *)_humanReadablePropertiesWithDictionary:(NSDictionary *)dict;
- (NSString *)_stringWithDateTime:(NSString *)dateTime subsecTime:(NSString *)subsecTime;
@end

#pragma mark -
@implementation PGInspectorPanelController

- (IBAction)changeSearch:(id)sender
{
	NSMutableDictionary *const matchingProperties = [NSMutableDictionary dictionary];
	NSArray *const terms = [[searchField stringValue] PG_searchTerms];
	for(NSString *const label in _properties) {
		NSString *const value = [_properties objectForKey:label];
		if([label PG_matchesSearchTerms:terms] || [[value description] PG_matchesSearchTerms:terms]) {
			[matchingProperties setObject:value forKey:label];
		}
	}
	[_matchingProperties release];
	_matchingProperties = [matchingProperties copy];
	[_matchingLabels release];
	_matchingLabels = [[[matchingProperties allKeys] sortedArrayUsingSelector:@selector(compare:)] copy];
	[propertiesTable reloadData];
	[self _updateColumnWidths];
}
- (IBAction)copy:(id)sender
{
	NSMutableString *const string = [NSMutableString string];
	NSIndexSet *const indexes = [propertiesTable selectedRowIndexes];
	NSUInteger i = [indexes firstIndex];
	for(; NSNotFound != i; i = [indexes indexGreaterThanIndex:i]) {
		NSString *const label = [_matchingLabels objectAtIndex:i];
		[string appendFormat:@"%@: %@\n", label, [_matchingProperties objectForKey:label]];
	}
	NSPasteboard *const pboard = [NSPasteboard generalPasteboard];
	[pboard declareTypes:[NSArray arrayWithObject:NSPasteboardTypeString] owner:nil];
	[pboard setString:string forType:NSPasteboardTypeString];
}

- (void)displayControllerActiveNodeWasRead:(NSNotification *)aNotif
{
	[_properties release];
	_properties = [[self _humanReadablePropertiesWithDictionary:[[[[self displayController] activeNode] resourceAdapter] imageProperties]] copy];
	[self changeSearch:nil];
}

#pragma mark -PGInspectorPanelController(Private)

- (void)_updateColumnWidths
{
//	[labelColumn setWidth:[labelColumn PG_zoomedWidth]];
//	[valueColumn setWidth:NSWidth([propertiesTable bounds]) - [labelColumn width]];
}
- (NSDictionary *)_humanReadablePropertiesWithDictionary:(NSDictionary *)dict
{
	NSDictionary *const keyLabels = [NSDictionary dictionaryWithObjectsAndKeys:
		@"Size (bytes)", (NSString *)kCGImagePropertyFileSize,		//	2022/10/15 added
		@"Color Model", (NSString *)kCGImagePropertyColorModel,
		@"Profile Name", (NSString *)kCGImagePropertyProfileName,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"TIFF", @".",
			@"Compression", (NSString *)kCGImagePropertyTIFFCompression,
			@"Photometric Interpretation", (NSString *)kCGImagePropertyTIFFPhotometricInterpretation,
			@"Document Name", (NSString *)kCGImagePropertyTIFFDocumentName,
			@"Image Description", (NSString *)kCGImagePropertyTIFFImageDescription,
			@"Make", (NSString *)kCGImagePropertyTIFFMake,
			@"Model", (NSString *)kCGImagePropertyTIFFModel,
			@"Software", (NSString *)kCGImagePropertyTIFFSoftware,
			@"Transfer Function", (NSString *)kCGImagePropertyTIFFTransferFunction,
			@"Artist", (NSString *)kCGImagePropertyTIFFArtist,
			@"Host Computer", (NSString *)kCGImagePropertyTIFFHostComputer,
			@"Copyright", (NSString *)kCGImagePropertyTIFFCopyright,
			@"White Point", (NSString *)kCGImagePropertyTIFFWhitePoint,
			@"Primary Chromaticities", (NSString *)kCGImagePropertyTIFFPrimaryChromaticities,
			nil], (NSString *)kCGImagePropertyTIFFDictionary,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"JFIF", @".",
			@"Progressive", (NSString *)kCGImagePropertyJFIFIsProgressive,
			nil], (NSString *)kCGImagePropertyJFIFDictionary,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"Exif", @".",
			@"Exposure Time", (NSString *)kCGImagePropertyExifExposureTime,
			@"F Number", (NSString *)kCGImagePropertyExifFNumber,
			@"Exposure Program", (NSString *)kCGImagePropertyExifExposureProgram,
			@"Spectral Sensitivity", (NSString *)kCGImagePropertyExifSpectralSensitivity,
			@"OECF", (NSString *)kCGImagePropertyExifOECF,
			@"Components Configuration", (NSString *)kCGImagePropertyExifComponentsConfiguration,
			@"Compressed BPP", (NSString *)kCGImagePropertyExifCompressedBitsPerPixel,
			@"Shutter Speed", (NSString *)kCGImagePropertyExifShutterSpeedValue,
			@"Aperture", (NSString *)kCGImagePropertyExifApertureValue,
			@"Brightness", (NSString *)kCGImagePropertyExifBrightnessValue,
			@"Exposure Bias", (NSString *)kCGImagePropertyExifExposureBiasValue,
			@"Max Aperture", (NSString *)kCGImagePropertyExifMaxApertureValue,
			@"Subject Distance", (NSString *)kCGImagePropertyExifSubjectDistance,
			@"Metering Mode", (NSString *)kCGImagePropertyExifMeteringMode,
			@"Light Source", (NSString *)kCGImagePropertyExifLightSource,
			@"Flash", (NSString *)kCGImagePropertyExifFlash,
			@"Focal Length", (NSString *)kCGImagePropertyExifFocalLength,
			@"Subject Area", (NSString *)kCGImagePropertyExifSubjectArea,
			@"Maker Note", (NSString *)kCGImagePropertyExifMakerNote,
			@"User Comment", (NSString *)kCGImagePropertyExifUserComment,
			@"Color Space", (NSString *)kCGImagePropertyExifColorSpace,
			@"Related Sound File", (NSString *)kCGImagePropertyExifRelatedSoundFile,
			@"Flash Energy", (NSString *)kCGImagePropertyExifFlashEnergy,
			@"Spatial Frequency Response", (NSString *)kCGImagePropertyExifSpatialFrequencyResponse,
			@"Focal Plane X Resolution", (NSString *)kCGImagePropertyExifFocalPlaneXResolution,
			@"Focal Plane Y Resolution", (NSString *)kCGImagePropertyExifFocalPlaneYResolution,
			@"Focal Plane Resolution Unit", (NSString *)kCGImagePropertyExifFocalPlaneResolutionUnit,
			@"Subject Location", (NSString *)kCGImagePropertyExifSubjectLocation,
			@"Exposure Index", (NSString *)kCGImagePropertyExifExposureIndex,
			@"Sensing Method", (NSString *)kCGImagePropertyExifSensingMethod,
			@"File Source", (NSString *)kCGImagePropertyExifFileSource,
			@"Scene Type", (NSString *)kCGImagePropertyExifSceneType,
			@"Custom Rendered", (NSString *)kCGImagePropertyExifCustomRendered,
			@"Exposure Mode", (NSString *)kCGImagePropertyExifExposureMode,
			@"White Balance", (NSString *)kCGImagePropertyExifWhiteBalance,
			@"Digital Zoom Ratio", (NSString *)kCGImagePropertyExifDigitalZoomRatio,
			@"Focal Length (35mm Film)", (NSString *)kCGImagePropertyExifFocalLenIn35mmFilm,
			@"Scene Capture Type", (NSString *)kCGImagePropertyExifSceneCaptureType,
			@"Gain Control", (NSString *)kCGImagePropertyExifGainControl,
			@"Contrast", (NSString *)kCGImagePropertyExifContrast,
			@"Saturation", (NSString *)kCGImagePropertyExifSaturation,
			@"Sharpness", (NSString *)kCGImagePropertyExifSharpness,
			@"Device Setting Description", (NSString *)kCGImagePropertyExifDeviceSettingDescription,
			@"Subject Dist Range", (NSString *)kCGImagePropertyExifSubjectDistRange,
			@"Image Unique ID", (NSString *)kCGImagePropertyExifImageUniqueID,
			@"Gamma", (NSString *)kCGImagePropertyExifGamma,
			nil], (NSString *)kCGImagePropertyExifDictionary,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"Exif (Aux)", @".",
			@"Lens Model", (NSString *)kCGImagePropertyExifAuxLensModel,
			@"Serial Number", (NSString *)kCGImagePropertyExifAuxSerialNumber,
			@"Lens ID", (NSString *)kCGImagePropertyExifAuxLensID,
			@"Lens Serial Number", (NSString *)kCGImagePropertyExifAuxLensSerialNumber,
			@"Image Number", (NSString *)kCGImagePropertyExifAuxImageNumber,
			@"Flash Compensation", (NSString *)kCGImagePropertyExifAuxFlashCompensation,
			@"Owner Name", (NSString *)kCGImagePropertyExifAuxOwnerName,
			@"Firmware", (NSString *)kCGImagePropertyExifAuxFirmware,
			nil], (NSString *)kCGImagePropertyExifAuxDictionary,
		nil];
	NSMutableDictionary *const properties = [[[[dict PG_replacementUsingObject:keyLabels preserveUnknown:NO getTopLevelKey:NULL] PG_flattenedDictionary] mutableCopy] autorelease];

	// TODO: Create special formatters for certain properties.
	/*
		kCGImagePropertyExifFNumber (?)
		kCGImagePropertyExifExposureProgram (?)
		kCGImagePropertyExifISOSpeedRatings (?)

		Check other properties as well.
	*/

	NSNumber *const depth = [dict objectForKey:(NSString *)kCGImagePropertyDepth];
	if(depth) [properties setObject:[NSString stringWithFormat:@"%lu bits per sample", [depth unsignedLongValue]] forKey:@"Depth"];

	NSNumber *const pixelWidth = [dict objectForKey:(NSString *)kCGImagePropertyPixelWidth];
	NSNumber *const pixelHeight = [dict objectForKey:(NSString *)kCGImagePropertyPixelHeight];
	if(pixelWidth || pixelHeight) [properties setObject:[NSString stringWithFormat:@"%lux%lu", [pixelWidth unsignedLongValue], [pixelHeight unsignedLongValue]] forKey:@"Pixel Count"];

	NSNumber *const densityWidth = [dict objectForKey:(NSString *)kCGImagePropertyDPIWidth];
	NSNumber *const densityHeight = [dict objectForKey:(NSString *)kCGImagePropertyDPIHeight];
	if(densityWidth || densityHeight) [properties setObject:[NSString stringWithFormat:PGEqualObjects(densityWidth, densityHeight) ? @"%lux%lu DPI" : @"%lux%lu DPI", (unsigned long)round([densityWidth doubleValue]), (unsigned long)round([densityHeight doubleValue])] forKey:@"Pixel Density"];

	if([[dict objectForKey:(NSString *)kCGImagePropertyHasAlpha] boolValue]) [properties setObject:@"Yes" forKey:@"Alpha"];

	PGOrientation const orientation = PGOrientationWithTIFFOrientation([[dict objectForKey:(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue]);
	if(PGUpright != orientation) [properties setObject:PGLocalizedStringWithOrientation(orientation) forKey:@"Orientation"];

	NSDictionary *const TIFFDict = [dict objectForKey:(NSString *)kCGImagePropertyTIFFDictionary];
	NSDictionary *const exifDict = [dict objectForKey:(NSString *)kCGImagePropertyExifDictionary];

	NSString *const dateTime = [self _stringWithDateTime:[TIFFDict objectForKey:(NSString *)kCGImagePropertyTIFFDateTime] subsecTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifSubsecTime]];
	[properties PG_setObject:dateTime forKey:@"Date/Time"];

#if 1
	NSString *const dateTimeOriginal = [self _stringWithDateTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifDateTimeOriginal] subsecTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifSubsecTimeOriginal]];
#else
	NSString *const dateTimeOriginal = [self _stringWithDateTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifDateTimeOriginal] subsecTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifSubsecTimeOrginal]];
#endif
	if(!PGEqualObjects(dateTime, dateTimeOriginal)) [properties PG_setObject:dateTimeOriginal forKey:@"Date/Time (Original)"];

	NSString *const dateTimeDigitized = [self _stringWithDateTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifDateTimeDigitized] subsecTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifSubsecTimeDigitized]];
	if(!PGEqualObjects(dateTime, dateTimeDigitized)) [properties PG_setObject:dateTimeDigitized forKey:@"Date/Time (Digitized)"];

	return properties;
}
- (NSString *)_stringWithDateTime:(NSString *)dateTime subsecTime:(NSString *)subsecTime
{
	if(!dateTime) return nil;
	if(!subsecTime) return dateTime;
	return [NSString stringWithFormat:@"%@.%@", dateTime, subsecTime];
}

#pragma mark -PGFloatingPanelController

- (NSString *)nibName
{
	return @"PGInspector";
}
- (BOOL)setDisplayController:(PGDisplayController *)controller
{
	PGDisplayController *const oldController = [self displayController];
	if(![super setDisplayController:controller]) return NO;
	[oldController PG_removeObserver:self name:PGDisplayControllerActiveNodeWasReadNotification];
	[[self displayController] PG_addObserver:self selector:@selector(displayControllerActiveNodeWasRead:) name:PGDisplayControllerActiveNodeWasReadNotification];
	[self displayControllerActiveNodeWasRead:nil];
	return YES;
}

#pragma mark -NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self _updateColumnWidths];
}

#pragma mark -NSObject

- (void)dealloc
{
	[propertiesTable setDelegate:nil];
	[propertiesTable setDataSource:nil];
	[_properties release];
	[_matchingProperties release];
	[_matchingLabels release];
	[super dealloc];
}

#pragma mark id<NSMenuValidation>

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = [anItem action];
	if(@selector(copy:) == action && ![[propertiesTable selectedRowIndexes] count]) return NO;
	return [super validateMenuItem:anItem];
}

#pragma mark id<NSTableViewDataSource>

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [_matchingLabels count];
}

/* This method is required for the "Cell Based" TableView, and is optional for the "View Based" TableView. If implemented in the latter case, the value will be set to the view at a given row/column if the view responds to -setObjectValue: (such as NSControl and NSTableCellView). Note that NSTableCellView does not actually display the objectValue, and its value is to be used for bindings. See NSTableCellView.h for more information.
 */
- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{//id<NSTableViewDataSource>* a = nil;
#if 0
	assert(tableColumn == labelColumn);
	return _matchingLabels[row];
#else
	NSString *const label = [_matchingLabels objectAtIndex:row];
//printf("%p\n", tableColumn);
	if(tableColumn == labelColumn) {
		return label;
	} else if(tableColumn == valueColumn) {
		return [_matchingProperties objectForKey:label];
	}
	return nil;
#endif
}

#pragma mark id<NSTableViewDelegate>

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{//id<NSTableViewDelegate>* a = nil;
	if(tableColumn == labelColumn) {
		NSTextField*	result = [[NSTextField new] autorelease];
		result.drawsBackground	=	NO;
		result.bordered			=	NO;
		result.bezeled			=	NO;
		result.editable			=	NO;
	//	result.bezelStyle		=	;

		result.font				=	[NSFont boldSystemFontOfSize:0.0];
		result.alignment		=	NSTextAlignmentRight;
		return result;
	} else if(tableColumn == valueColumn) {
		NSTextField*	result = [[NSTextField new] autorelease];
		result.drawsBackground	=	NO;
		result.bordered			=	NO;
		result.bezeled			=	NO;
		result.editable			=	NO;

		result.font				=	[NSFont systemFontOfSize:0.0];
		result.alignment		=	NSTextAlignmentLeft;
		return result;
	}
	return nil;
}

/* - (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if(tableColumn == labelColumn) {
		[(NSTextFieldCell*)cell setAlignment:NSTextAlignmentRight];
		[cell setFont:[[NSFontManager sharedFontManager] convertFont:[cell font] toHaveTrait:NSBoldFontMask]];
	}
} */

@end

#pragma mark -
@implementation NSObject(PGAdditions)

- (id)PG_replacementUsingObject:(id)replacement preserveUnknown:(BOOL)preserve getTopLevelKey:(out id *)outKey
{
	if(!replacement) return preserve ? self : nil;
	if(outKey) *outKey = replacement;
	return self;
}

@end

#pragma mark -
@implementation NSDictionary(PGAdditions)

- (NSDictionary *)PG_flattenedDictionary
{
	NSMutableDictionary *const results = [NSMutableDictionary dictionary];
	for(id const key in self) {
		id const obj = [self objectForKey:key];
		if([obj isKindOfClass:[NSDictionary class]]) [results addEntriesFromDictionary:obj];
		else [results setObject:obj forKey:key];
	}
	return results;
}

#pragma mark -NSObject(PGAdditions)

- (id)PG_replacementUsingObject:(id)replacement preserveUnknown:(BOOL)preserve getTopLevelKey:(out id *)outKey
{
	if(![replacement isKindOfClass:[NSDictionary class]]) return [super PG_replacementUsingObject:replacement preserveUnknown:preserve getTopLevelKey:outKey];
	NSMutableDictionary *const result = [NSMutableDictionary dictionary];
	for(id const key in self) {
		id replacementKey = key;
		id const replacementObj = [[self objectForKey:key] PG_replacementUsingObject:[(NSDictionary *)replacement objectForKey:key] preserveUnknown:preserve getTopLevelKey:&replacementKey];
		if(replacementObj) [result setObject:replacementObj forKey:replacementKey];
	}
	if(outKey) *outKey = [(NSDictionary *)replacement objectForKey:@"."];
	return result;
}

@end

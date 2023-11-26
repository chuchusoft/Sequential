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

#if __has_feature(objc_arc)

@interface PGInspectorPanelController ()

@property (nonatomic, weak) IBOutlet NSTableView *propertiesTable;
@property (nonatomic, weak) IBOutlet NSTableColumn *labelColumn;
@property (nonatomic, weak) IBOutlet NSTableColumn *valueColumn;
@property (nonatomic, weak) IBOutlet NSSearchField *searchField;
@property (nonatomic, strong) NSDictionary *properties;
@property (nonatomic, strong) NSDictionary *matchingProperties;
@property (nonatomic, strong) NSArray *matchingLabels;

- (void)_updateColumnWidths;
- (NSDictionary *)_humanReadablePropertiesWithDictionary:(NSDictionary *)dict;
- (NSString *)_stringWithDateTime:(NSString *)dateTime subsecTime:(NSString *)subsecTime;

@end

#else

@interface PGInspectorPanelController(Private)
- (void)_updateColumnWidths;
- (NSDictionary *)_humanReadablePropertiesWithDictionary:(NSDictionary *)dict;
- (NSString *)_stringWithDateTime:(NSString *)dateTime subsecTime:(NSString *)subsecTime;
@end

#endif

//	MARK: -
@implementation PGInspectorPanelController

- (IBAction)changeSearch:(id)sender
{
	NSMutableDictionary *const matchingProperties = [NSMutableDictionary dictionary];
#if __has_feature(objc_arc)
	NSArray *const terms = [_searchField.stringValue PG_searchTerms];
#else
	NSArray *const terms = [[searchField stringValue] PG_searchTerms];
#endif
	for(NSString *const label in _properties) {
		NSString *const value = _properties[label];
		if([label PG_matchesSearchTerms:terms] || [value.description PG_matchesSearchTerms:terms]) {
			matchingProperties[label] = value;
		}
	}
#if !__has_feature(objc_arc)
	[_matchingProperties release];
#endif
	_matchingProperties = [matchingProperties copy];
#if !__has_feature(objc_arc)
	[_matchingLabels release];
#endif
	_matchingLabels = [[matchingProperties.allKeys sortedArrayUsingSelector:@selector(compare:)] copy];
#if __has_feature(objc_arc)
	[_propertiesTable reloadData];
#else
	[propertiesTable reloadData];
#endif
	[self _updateColumnWidths];
}
- (IBAction)copy:(id)sender
{
	NSMutableString *const string = [NSMutableString string];
#if __has_feature(objc_arc)
	NSIndexSet *const indexes = _propertiesTable.selectedRowIndexes;
#else
	NSIndexSet *const indexes = [propertiesTable selectedRowIndexes];
#endif
	NSUInteger i = indexes.firstIndex;
	for(; NSNotFound != i; i = [indexes indexGreaterThanIndex:i]) {
		NSString *const label = _matchingLabels[i];
		[string appendFormat:@"%@: %@\n", label, _matchingProperties[label]];
	}
	NSPasteboard *const pboard = [NSPasteboard generalPasteboard];
	[pboard declareTypes:@[NSPasteboardTypeString] owner:nil];
	[pboard setString:string forType:NSPasteboardTypeString];
}

- (void)displayControllerActiveNodeWasRead:(NSNotification *)aNotif
{
	NSDictionary *d = self.displayController.activeNode.resourceAdapter.imageProperties;
#if __has_feature(objc_arc)
	_properties = [self _humanReadablePropertiesWithDictionary:d];
#else
	[_properties release];
	//	no need to -copy because the object stored in _properties is not shared
//	_properties = [[self _humanReadablePropertiesWithDictionary:d] copy];
	_properties = [[self _humanReadablePropertiesWithDictionary:d] retain];
#endif

	[self changeSearch:nil];
}

//	MARK: - PGInspectorPanelController(Private)

- (void)_updateColumnWidths
{
//	[_labelColumn setWidth:[_labelColumn PG_zoomedWidth]];
//	[_valueColumn setWidth:NSWidth([_propertiesTable bounds]) - [_labelColumn width]];
}
- (NSDictionary *)_humanReadablePropertiesWithDictionary:(NSDictionary *)dict
{
#if __has_feature(objc_arc)
	NSDictionary *const keyLabels = @{
		(NSString *)kCGImagePropertyFileSize: @"File Size (bytes)",	//	2022/10/15 added
	//	(NSString *)kCGImagePropertyPixelHeight: @"Pixel Height",	[special case]
	//	(NSString *)kCGImagePropertyPixelWidth: @"Pixel Width",		[special case]
	//	(NSString *)kCGImagePropertyDPIHeight: @"DPI Height",		[special case]
	//	(NSString *)kCGImagePropertyDPIWidth: @"DPI Width",			[special case]
	//	(NSString *)kCGImagePropertyDepth: @"Bit Depth",			[special case]
		(NSString *)kCGImagePropertyIsFloat: @"Floating Point Pixels",	//	2023/08/14 added
		(NSString *)kCGImagePropertyIsIndexed: @"Indexed (palette) Pixels",	//	2023/08/14 added
	//	(NSString *)kCGImagePropertyHasAlpha: @"Alpha Channel Present",
		(NSString *)kCGImagePropertyColorModel: @"Color Model",
		(NSString *)kCGImagePropertyProfileName: @"Profile Name",
#else
	NSDictionary *const keyLabels = [NSDictionary dictionaryWithObjectsAndKeys:
		@"File Size (bytes)", (NSString *)kCGImagePropertyFileSize,	//	2022/10/15 added
	//	@"Pixel Height", (NSString *)kCGImagePropertyPixelHeight,	[special case]
	//	@"Pixel Width", (NSString *)kCGImagePropertyPixelWidth,		[special case]
	//	@"DPI Height", (NSString *)kCGImagePropertyDPIHeight,		[special case]
	//	@"DPI Width", (NSString *)kCGImagePropertyDPIWidth,			[special case]
	//	@"Bit Depth", (NSString *)kCGImagePropertyDepth,			[special case]
		@"Floating Point Pixels", (NSString *)kCGImagePropertyIsFloat,	//	2023/08/14 added
		@"Indexed (palette) Pixels", (NSString *)kCGImagePropertyIsIndexed,	//	2023/08/14 added
	//	@"Alpha Channel Present", (NSString *)kCGImagePropertyHasAlpha,
		@"Color Model", (NSString *)kCGImagePropertyColorModel,
		@"Profile Name", (NSString *)kCGImagePropertyProfileName,
#endif

#if __has_feature(objc_arc)
		(NSString *)kCGImagePropertyTIFFDictionary: @{
			@".": @"TIFF",
			(NSString *)kCGImagePropertyTIFFCompression: @"Compression",
			(NSString *)kCGImagePropertyTIFFPhotometricInterpretation: @"Photometric Interpretation",
			(NSString *)kCGImagePropertyTIFFDocumentName: @"Document Name",
			(NSString *)kCGImagePropertyTIFFImageDescription: @"Image Description",
			(NSString *)kCGImagePropertyTIFFMake: @"Make",
			(NSString *)kCGImagePropertyTIFFModel: @"Model",
			(NSString *)kCGImagePropertyTIFFSoftware: @"Software",
			(NSString *)kCGImagePropertyTIFFTransferFunction: @"Transfer Function",
			(NSString *)kCGImagePropertyTIFFArtist: @"Artist",
			(NSString *)kCGImagePropertyTIFFHostComputer: @"Host Computer",
			(NSString *)kCGImagePropertyTIFFCopyright: @"Copyright",
			(NSString *)kCGImagePropertyTIFFWhitePoint: @"White Point",
			(NSString *)kCGImagePropertyTIFFPrimaryChromaticities: @"Primary Chromaticities" },
#else
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
#endif

#if __has_feature(objc_arc)
		(NSString *)kCGImagePropertyJFIFDictionary: @{
			@".": @"JFIF",
			(NSString *)kCGImagePropertyJFIFIsProgressive: @"Progressive" },
#else
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"JFIF", @".",
			@"Progressive", (NSString *)kCGImagePropertyJFIFIsProgressive,
			nil], (NSString *)kCGImagePropertyJFIFDictionary,
#endif

		//	TODO: add HEIC dictionary here...

#if __has_feature(objc_arc)
		(NSString *)kCGImagePropertyExifDictionary: @{
			@".": @"Exif",
			(NSString *)kCGImagePropertyExifExposureTime: @"Exposure Time",
			(NSString *)kCGImagePropertyExifFNumber: @"F Number",
			(NSString *)kCGImagePropertyExifExposureProgram: @"Exposure Program",
			(NSString *)kCGImagePropertyExifSpectralSensitivity: @"Spectral Sensitivity",
		//	(NSString *)kCGImagePropertyExifISOSpeedRatings: @"ISO Speed Ratings",
			(NSString *)kCGImagePropertyExifOECF: @"OECF",
		/*	kCGImagePropertyExifSensitivityType
			kCGImagePropertyExifStandardOutputSensitivity
			kCGImagePropertyExifRecommendedExposureIndex
			kCGImagePropertyExifISOSpeed
			kCGImagePropertyExifISOSpeedLatitudeyyy
			kCGImagePropertyExifISOSpeedLatitudezzz
			kCGImagePropertyExifVersion
			kCGImagePropertyExifDateTimeOriginal
			kCGImagePropertyExifDateTimeDigitize
			kCGImagePropertyExifOffsetTime
			kCGImagePropertyExifOffsetTimeOriginal
			kCGImagePropertyExifOffsetTimeDigitized	*/
			(NSString *)kCGImagePropertyExifComponentsConfiguration: @"Components Configuration",
			(NSString *)kCGImagePropertyExifCompressedBitsPerPixel: @"Compressed BPP",
			(NSString *)kCGImagePropertyExifShutterSpeedValue: @"Shutter Speed",
			(NSString *)kCGImagePropertyExifApertureValue: @"Aperture",
			(NSString *)kCGImagePropertyExifBrightnessValue: @"Brightness",
			(NSString *)kCGImagePropertyExifExposureBiasValue: @"Exposure Bias",
			(NSString *)kCGImagePropertyExifMaxApertureValue: @"Max Aperture",
			(NSString *)kCGImagePropertyExifSubjectDistance: @"Subject Distance",
			(NSString *)kCGImagePropertyExifMeteringMode: @"Metering Mode",
			(NSString *)kCGImagePropertyExifLightSource: @"Light Source",
			(NSString *)kCGImagePropertyExifFlash: @"Flash",
			(NSString *)kCGImagePropertyExifFocalLength: @"Focal Length",
			(NSString *)kCGImagePropertyExifSubjectArea: @"Subject Area",
			(NSString *)kCGImagePropertyExifMakerNote: @"Maker Note",
			(NSString *)kCGImagePropertyExifUserComment: @"User Comment",
		//	kCGImagePropertyExifFlashPixVersion
			(NSString *)kCGImagePropertyExifColorSpace: @"Color Space",
		//	kCGImagePropertyExifPixelXDimension
		//	kCGImagePropertyExifPixelYDimension
			(NSString *)kCGImagePropertyExifRelatedSoundFile: @"Related Sound File",
			(NSString *)kCGImagePropertyExifFlashEnergy: @"Flash Energy",
			(NSString *)kCGImagePropertyExifSpatialFrequencyResponse: @"Spatial Frequency Response",
			(NSString *)kCGImagePropertyExifFocalPlaneXResolution: @"Focal Plane X Resolution",
			(NSString *)kCGImagePropertyExifFocalPlaneYResolution: @"Focal Plane Y Resolution",
			(NSString *)kCGImagePropertyExifFocalPlaneResolutionUnit: @"Focal Plane Resolution Unit",
			(NSString *)kCGImagePropertyExifSubjectLocation: @"Subject Location",
			(NSString *)kCGImagePropertyExifExposureIndex: @"Exposure Index",
			(NSString *)kCGImagePropertyExifSensingMethod: @"Sensing Method",
			(NSString *)kCGImagePropertyExifFileSource: @"File Source",
			(NSString *)kCGImagePropertyExifSceneType: @"Scene Type",
		//	kCGImagePropertyExifCFAPattern
			(NSString *)kCGImagePropertyExifCustomRendered: @"Custom Rendered",
			(NSString *)kCGImagePropertyExifExposureMode: @"Exposure Mode",
			(NSString *)kCGImagePropertyExifWhiteBalance: @"White Balance",
			(NSString *)kCGImagePropertyExifDigitalZoomRatio: @"Digital Zoom Ratio",
			(NSString *)kCGImagePropertyExifFocalLenIn35mmFilm: @"Focal Length (35mm Film)",
			(NSString *)kCGImagePropertyExifSceneCaptureType: @"Scene Capture Type",
			(NSString *)kCGImagePropertyExifGainControl: @"Gain Control",
			(NSString *)kCGImagePropertyExifContrast: @"Contrast",
			(NSString *)kCGImagePropertyExifSaturation: @"Saturation",
			(NSString *)kCGImagePropertyExifSharpness: @"Sharpness",
			(NSString *)kCGImagePropertyExifDeviceSettingDescription: @"Device Setting Description",
			(NSString *)kCGImagePropertyExifSubjectDistRange: @"Subject Dist Range",
			(NSString *)kCGImagePropertyExifImageUniqueID: @"Image Unique ID",
		/*	kCGImagePropertyExifCameraOwnerName
			kCGImagePropertyExifBodySerialNumber
			kCGImagePropertyExifLensSpecification
			kCGImagePropertyExifLensMake
			kCGImagePropertyExifLensModel
			kCGImagePropertyExifLensSerialNumber	*/
			(NSString *)kCGImagePropertyExifGamma: @"Gamma"
		/*	kCGImagePropertyExifCompositeImage
			kCGImagePropertyExifSourceImageNumberOfCompositeImage
			kCGImagePropertyExifSourceExposureTimesOfCompositeImage	*/
		},
		(NSString *)kCGImagePropertyExifAuxDictionary : @{
			@".": @"Exif (Aux)",
		//	kCGImagePropertyExifAuxLensInfo
			(NSString *)kCGImagePropertyExifAuxLensModel: @"Lens Model",
			(NSString *)kCGImagePropertyExifAuxSerialNumber: @"Serial Number",
			(NSString *)kCGImagePropertyExifAuxLensID: @"Lens ID",
			(NSString *)kCGImagePropertyExifAuxLensSerialNumber: @"Lens Serial Number",
			(NSString *)kCGImagePropertyExifAuxImageNumber: @"Image Number",
			(NSString *)kCGImagePropertyExifAuxFlashCompensation: @"Flash Compensation",
			(NSString *)kCGImagePropertyExifAuxOwnerName: @"Owner Name",
			(NSString *)kCGImagePropertyExifAuxFirmware: @"Firmware",
		},
#else
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"Exif", @".",
			@"Exposure Time", (NSString *)kCGImagePropertyExifExposureTime,
			@"F Number", (NSString *)kCGImagePropertyExifFNumber,
			@"Exposure Program", (NSString *)kCGImagePropertyExifExposureProgram,
			@"Spectral Sensitivity", (NSString *)kCGImagePropertyExifSpectralSensitivity,
		//	@"ISO Speed Ratings", (NSString *)kCGImagePropertyExifISOSpeedRatings,
			@"OECF", (NSString *)kCGImagePropertyExifOECF,
		/*
			kCGImagePropertyExifSensitivityType
			kCGImagePropertyExifStandardOutputSensitivity
			kCGImagePropertyExifRecommendedExposureIndex
			kCGImagePropertyExifISOSpeed
			kCGImagePropertyExifISOSpeedLatitudeyyy
			kCGImagePropertyExifISOSpeedLatitudezzz
			kCGImagePropertyExifVersion
			kCGImagePropertyExifDateTimeOriginal
			kCGImagePropertyExifDateTimeDigitize
			kCGImagePropertyExifOffsetTime
			kCGImagePropertyExifOffsetTimeOriginal
			kCGImagePropertyExifOffsetTimeDigitized
		 */
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
		//	kCGImagePropertyExifFlashPixVersion
			@"Color Space", (NSString *)kCGImagePropertyExifColorSpace,
		//	kCGImagePropertyExifPixelXDimension
		//	kCGImagePropertyExifPixelYDimension
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
		//	kCGImagePropertyExifCFAPattern
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
		/*
			kCGImagePropertyExifCameraOwnerName
			kCGImagePropertyExifBodySerialNumber
			kCGImagePropertyExifLensSpecification
			kCGImagePropertyExifLensMake
			kCGImagePropertyExifLensModel
			kCGImagePropertyExifLensSerialNumber
		 */
			@"Gamma", (NSString *)kCGImagePropertyExifGamma,
		/*
			kCGImagePropertyExifCompositeImage
			kCGImagePropertyExifSourceImageNumberOfCompositeImage
			kCGImagePropertyExifSourceExposureTimesOfCompositeImage
		 */
			nil], (NSString *)kCGImagePropertyExifDictionary,
		[NSDictionary dictionaryWithObjectsAndKeys:
			@"Exif (Aux)", @".",
		//	kCGImagePropertyExifAuxLensInfo
			@"Lens Model", (NSString *)kCGImagePropertyExifAuxLensModel,
			@"Serial Number", (NSString *)kCGImagePropertyExifAuxSerialNumber,
			@"Lens ID", (NSString *)kCGImagePropertyExifAuxLensID,
			@"Lens Serial Number", (NSString *)kCGImagePropertyExifAuxLensSerialNumber,
			@"Image Number", (NSString *)kCGImagePropertyExifAuxImageNumber,
			@"Flash Compensation", (NSString *)kCGImagePropertyExifAuxFlashCompensation,
			@"Owner Name", (NSString *)kCGImagePropertyExifAuxOwnerName,
			@"Firmware", (NSString *)kCGImagePropertyExifAuxFirmware,
			nil], (NSString *)kCGImagePropertyExifAuxDictionary,
#endif

		//	TODO: add GIF dictionary here...

		//	TODO: add PNG dictionary here...

		//	TODO: add APNG dictionary here...

		//	TODO: add WebP dictionary here...

		//	TODO: add GPS dictionary here...

		//	TODO: add IPTC dictionary here...

		//	TODO: add 8BIM dictionary here...

		//	TODO: add DNG dictionary here...

		//	TODO: add CIFF dictionary here...

		//	TODO: add Nikon dictionary here...

		//	TODO: add Canon dictionary here...

		//	TODO: add OpenEXR dictionary here...

		//	TODO: add TGA dictionary here...

#if __has_feature(objc_arc)
	};
#else
		nil];
#endif

	//	the returned object:
#if __has_feature(objc_arc)
	NSMutableDictionary *const properties = [[[dict PG_replacementUsingObject:keyLabels
															  preserveUnknown:NO
															   getTopLevelKey:NULL] PG_flattenedDictionary] mutableCopy];
#else
	NSMutableDictionary *const properties = [[[[dict PG_replacementUsingObject:keyLabels preserveUnknown:NO getTopLevelKey:NULL] PG_flattenedDictionary] mutableCopy] autorelease];
#endif

	//	2023/08/14 any values whose type conforms to NSArray will be converted to a string
	//	because NSArrays are displayed as "(\n<val0>,\n<val1>,\n<val2>,\n ... <val-last>\n)"
	{
		NSMutableDictionary *const replacements = [NSMutableDictionary new];
		[properties enumerateKeysAndObjectsUsingBlock:^(NSString* key, id obj, BOOL *stop) {
			if([obj isKindOfClass:NSArray.class]) {
				NSString* value = [[[obj description] stringByReplacingOccurrencesOfString:@"\n" withString:@""]
					stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"() "]];
				replacements[key] = value;
			}
		}];

		[properties addEntriesFromDictionary:replacements];
#if !__has_feature(objc_arc)
		[replacements release];
#endif
	}

	// TODO: Create special formatters for certain properties.
	/*
		kCGImagePropertyExifFNumber (?)
		kCGImagePropertyExifExposureProgram (?)
		kCGImagePropertyExifISOSpeedRatings (?)

		Check other properties as well.
	*/
#if 0
	{
	//	id value = [dict objectForKey:(NSString *)kCGImagePropertyExifComponentsConfiguration];
	//	if(value)
	//		NSLog(@"kCGImagePropertyExifComponentsConfiguration value = %@, %@ (%@)",
	//				value, [value description], [[value class] description]);

		id value2 = [properties objectForKey:@"Components Configuration"];
		if(value2)
			NSLog(@"kCGImagePropertyExifComponentsConfiguration value = '%@' (%@), dict =\n%@\nproperties =\n%@",
					value2, [[value2 class] description], dict, properties);
	}
#endif

	NSNumber *const depth = dict[(NSString *)kCGImagePropertyDepth];
	if(depth)
		properties[@"Depth"] = [NSString stringWithFormat:@"%lu bits per sample", depth.unsignedLongValue];

	NSNumber *const pixelWidth = dict[(NSString *)kCGImagePropertyPixelWidth];
	NSNumber *const pixelHeight = dict[(NSString *)kCGImagePropertyPixelHeight];
	if(pixelWidth && pixelHeight)
		properties[@"Pixel Width x Height"] = [NSString stringWithFormat:@"%lu x %lu",
									pixelWidth.unsignedLongValue, pixelHeight.unsignedLongValue];

	NSNumber *const densityWidth = dict[(NSString *)kCGImagePropertyDPIWidth];
	NSNumber *const densityHeight = dict[(NSString *)kCGImagePropertyDPIHeight];
	if(densityWidth || densityHeight)
		properties[@"DPI Width x Height"] = [NSString stringWithFormat:@"%lu x %lu",
									(unsigned long) round(densityWidth.doubleValue),
									(unsigned long) round(densityHeight.doubleValue)];

	if([dict[(NSString *)kCGImagePropertyHasAlpha] boolValue])
		properties[@"Alpha"] = @"Yes";

	PGOrientation const orientation = PGOrientationWithTIFFOrientation([dict[(NSString *)kCGImagePropertyOrientation] unsignedIntegerValue]);
	if(PGUpright != orientation) properties[@"Orientation"] = PGLocalizedStringWithOrientation(orientation);

	NSDictionary *const TIFFDict = dict[(NSString *)kCGImagePropertyTIFFDictionary];
	NSDictionary *const exifDict = dict[(NSString *)kCGImagePropertyExifDictionary];

	NSString *const dateTime = [self _stringWithDateTime:TIFFDict[(NSString *)kCGImagePropertyTIFFDateTime] subsecTime:exifDict[(NSString *)kCGImagePropertyExifSubsecTime]];
	[properties PG_setObject:dateTime forKey:@"Date/Time (Created)"];

#if 1
	NSString *const dateTimeOriginal = [self _stringWithDateTime:exifDict[(NSString *)kCGImagePropertyExifDateTimeOriginal] subsecTime:exifDict[(NSString *)kCGImagePropertyExifSubsecTimeOriginal]];
#else
	NSString *const dateTimeOriginal = [self _stringWithDateTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifDateTimeOriginal] subsecTime:[exifDict objectForKey:(NSString *)kCGImagePropertyExifSubsecTimeOrginal]];
#endif
	if(!PGEqualObjects(dateTime, dateTimeOriginal)) [properties PG_setObject:dateTimeOriginal forKey:@"Date/Time (Original)"];

	NSString *const dateTimeDigitized = [self _stringWithDateTime:exifDict[(NSString *)kCGImagePropertyExifDateTimeDigitized] subsecTime:exifDict[(NSString *)kCGImagePropertyExifSubsecTimeDigitized]];
	if(!PGEqualObjects(dateTime, dateTimeDigitized)) [properties PG_setObject:dateTimeDigitized forKey:@"Date/Time (Digitized)"];

	return properties;
}

- (NSString *)_stringWithDateTime:(NSString *)dateTime subsecTime:(NSString *)subsecTime
{
	if(!dateTime) return nil;

	//	2023/08/12 change "2023:08:12 12:34:56" to "2023-08-12 12:34:56"
	NSError*				error = nil;
	NSRegularExpression*	regex = [NSRegularExpression
		regularExpressionWithPattern:@"([0-9]{4}):([0-9]{2}):([0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})"
							 options:0
							   error:&error];
	NSRange		range = NSMakeRange(0, dateTime.length);
	NSUInteger	matches = [regex numberOfMatchesInString:dateTime options:0 range:range];
	if(1 == matches)
		dateTime = [regex stringByReplacingMatchesInString:dateTime
												   options:0
													 range:range
											//withTemplate:@"$1/$2/$3"];
											  withTemplate:@"$1-$2-$3"];

	if(!subsecTime) return dateTime;
	return [NSString stringWithFormat:@"%@.%@", dateTime, subsecTime];
}

//	MARK: - PGFloatingPanelController

- (NSString *)nibName
{
	return @"PGInspector";
}
- (BOOL)setDisplayControllerReturningWasChanged:(PGDisplayController *)controller
//- (BOOL)setDisplayController:(PGDisplayController *)controller
{
	PGDisplayController *const oldController = self.displayController;
	if(![super setDisplayControllerReturningWasChanged:controller]) return NO;
	[oldController PG_removeObserver:self name:PGDisplayControllerActiveNodeWasReadNotification];
	[self.displayController PG_addObserver:self selector:@selector(displayControllerActiveNodeWasRead:) name:PGDisplayControllerActiveNodeWasReadNotification];
	[self displayControllerActiveNodeWasRead:nil];
	return YES;
}

//	MARK: - NSWindowController

- (void)windowDidLoad
{
	[super windowDidLoad];
	[self _updateColumnWidths];
}

//	MARK: - NSObject

- (void)dealloc
{
#if __has_feature(objc_arc)
	[_propertiesTable setDelegate:nil];
	[_propertiesTable setDataSource:nil];
#else
	[propertiesTable setDelegate:nil];
	[propertiesTable setDataSource:nil];
	[_properties release];
	[_matchingProperties release];
	[_matchingLabels release];
	[super dealloc];
#endif
}

//	MARK: id<NSMenuValidation>

- (BOOL)validateMenuItem:(NSMenuItem *)anItem
{
	SEL const action = anItem.action;
#if __has_feature(objc_arc)
	if(@selector(copy:) == action && !_propertiesTable.selectedRowIndexes.count) return NO;
#else
	if(@selector(copy:) == action && ![[propertiesTable selectedRowIndexes] count]) return NO;
#endif
	return [super validateMenuItem:anItem];
}

//	MARK: id<NSTableViewDataSource>

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return _matchingLabels.count;
}

/* This method is required for the "Cell Based" TableView, and is optional for the "View Based" TableView. If implemented in the latter case, the value will be set to the view at a given row/column if the view responds to -setObjectValue: (such as NSControl and NSTableCellView). Note that NSTableCellView does not actually display the objectValue, and its value is to be used for bindings. See NSTableCellView.h for more information.
 */
- (nullable id)tableView:(NSTableView *)tableView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn row:(NSInteger)row
{//id<NSTableViewDataSource>* a = nil;
#if 0
	NSParameterAssert(tableColumn == _labelColumn);
	return _matchingLabels[row];
#else
	NSString *const label = _matchingLabels[row];
//printf("%p\n", tableColumn);
	#if __has_feature(objc_arc)
	if(tableColumn == _labelColumn) {
		return label;
	} else if(tableColumn == _valueColumn) {
		return _matchingProperties[label];
	}
	#else
	if(tableColumn == labelColumn) {
		return label;
	} else if(tableColumn == valueColumn) {
		return [_matchingProperties objectForKey:label];
	}
	#endif
	return nil;
#endif
}

//	MARK: id<NSTableViewDelegate>

- (nullable NSView *)tableView:(NSTableView *)tableView
			viewForTableColumn:(nullable NSTableColumn *)tableColumn
						   row:(NSInteger)row
{
#if __has_feature(objc_arc)
	if(tableColumn == _labelColumn) {
		NSTextField *result = [NSTextField new];
		result.drawsBackground	=	NO;
		result.bordered			=	NO;
		result.bezeled			=	NO;
		result.editable			=	NO;
	//	result.bezelStyle		=	;

		result.font				=	[NSFont boldSystemFontOfSize:0.0];
		result.alignment		=	NSTextAlignmentRight;
		return result;
	} else if(tableColumn == _valueColumn) {
		NSTextField *result = [NSTextField new];
		result.drawsBackground	=	NO;
		result.bordered			=	NO;
		result.bezeled			=	NO;
		result.editable			=	NO;

		result.font				=	[NSFont systemFontOfSize:0.0];
		result.alignment		=	NSTextAlignmentLeft;
		return result;
	}
	return nil;
#else
	if(tableColumn == labelColumn) {
		NSTextField *result = [[NSTextField new] autorelease];
		result.drawsBackground	=	NO;
		result.bordered			=	NO;
		result.bezeled			=	NO;
		result.editable			=	NO;
	//	result.bezelStyle		=	;

		result.font				=	[NSFont boldSystemFontOfSize:0.0];
		result.alignment		=	NSTextAlignmentRight;
		return result;
	} else if(tableColumn == valueColumn) {
		NSTextField *result = [[NSTextField new] autorelease];
		result.drawsBackground	=	NO;
		result.bordered			=	NO;
		result.bezeled			=	NO;
		result.editable			=	NO;

		result.font				=	[NSFont systemFontOfSize:0.0];
		result.alignment		=	NSTextAlignmentLeft;
		return result;
	}
	return nil;
#endif
}

/* - (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if(tableColumn == _labelColumn) {
		[(NSTextFieldCell*)cell setAlignment:NSTextAlignmentRight];
		[cell setFont:[[NSFontManager sharedFontManager] convertFont:[cell font] toHaveTrait:NSBoldFontMask]];
	}
} */

@end

//	MARK: -
@implementation NSObject(PGAdditions)

- (id)PG_replacementUsingObject:(id)replacement preserveUnknown:(BOOL)preserve getTopLevelKey:(out id *)outKey
{
	if(!replacement)
		return preserve ? self : nil;
	if(outKey)
		*outKey = replacement;
	return self;
}

@end

//	MARK: -
@implementation NSDictionary(PGAdditions)

- (NSDictionary *)PG_flattenedDictionary
{
	NSMutableDictionary *const results = [NSMutableDictionary dictionary];
	for(id const key in self) {
		id const obj = self[key];
		if([obj isKindOfClass:[NSDictionary class]]) [results addEntriesFromDictionary:obj];
		else results[key] = obj;
	}
	return results;
}

//	MARK: - NSObject(PGAdditions)

- (id)PG_replacementUsingObject:(id)replacement preserveUnknown:(BOOL)preserve getTopLevelKey:(out id *)outKey
{
	if(![replacement isKindOfClass:[NSDictionary class]])
		return [super PG_replacementUsingObject:replacement
								preserveUnknown:preserve
								 getTopLevelKey:outKey];

	NSMutableDictionary *const result = [NSMutableDictionary dictionary];
	for(id const key in self) {
		id replacementKey = key;
		id const replacementObj = [self[key] PG_replacementUsingObject:((NSDictionary *)replacement)[key] preserveUnknown:preserve getTopLevelKey:&replacementKey];

		if(replacementObj)
			result[replacementKey] = replacementObj;
	}

	if(outKey)
		*outKey = ((NSDictionary *)replacement)[@"."];

	return result;
}

@end

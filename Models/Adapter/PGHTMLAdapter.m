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
#import "PGHTMLAdapter.h"

// Models
#import "PGNode.h"
#import "PGResourceIdentifier.h"

// Controllers
#import "PGDocumentController.h"

// Other Sources
#import <WebKit/WebKit.h>	//	#import "PGWebKitAdditions.h"

NSString *const PGDOMDocumentKey = @"PGDOMDocument";

#if __has_feature(objc_arc)

@interface PGHTMLAdapter ()

@property (nonatomic, strong) WKWebView *webView;	//	WebView *_webView;
@property (nonatomic, strong) WKNavigation *navigation;

- (void)_clearWebView;

@end

#else

@interface PGHTMLAdapter(Private)

- (void)_clearWebView;

@end

#endif

//	MARK: -
@implementation PGHTMLAdapter

- (void)_clearWebView
{
	[_webView stopLoading:self];
	_webView.navigationDelegate = nil;	//	[_webView setFrameLoadDelegate:nil];
#if !__has_feature(objc_arc)
	[_webView autorelease];
#endif
	_webView = nil;

#if !__has_feature(objc_arc)
	[_navigation autorelease];
#endif
	_navigation = nil;
}

//	MARK: - PGContainerAdapter

- (PGRecursionPolicy)descendantRecursionPolicy
{
	return PGRecurseNoFurther;
}

//	MARK: - PGResourceAdapter

- (void)load
{
	NSParameterAssert(!_webView);
	PGDataProvider *const dp = [self dataProvider];
	NSData *const data = [dp data];
	if(!data)
		return [[self node] fallbackFromFailedAdapter:self];
#if 1
	{
		WKPreferences* preferences = [WKPreferences new];
		preferences.javaEnabled = NO;
		preferences.plugInsEnabled = NO;
		preferences.javaScriptEnabled = NO;
		preferences.javaScriptCanOpenWindowsAutomatically = NO;
	//	preferences.loadsImagesAutomatically = NO;
		if(@available(macOS 10.15, *))
			preferences.fraudulentWebsiteWarningEnabled = NO;
		preferences.tabFocusesLinks = NO;
		if(@available(macOS 11.3, *))
			preferences.textInteractionEnabled = NO;

		{
			WKWebViewConfiguration* webViewConfiguration = [WKWebViewConfiguration new];
			webViewConfiguration.preferences = preferences;
			_webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:webViewConfiguration];
	#if !__has_feature(objc_arc)
			[webViewConfiguration release];
	#endif
		}
	#if !__has_feature(objc_arc)
		[preferences release];
	#endif
	}
	_webView.navigationDelegate = self;

	NSURLResponse *const response = [dp response];
	WKNavigation* nav;
	if(response)
		nav = [_webView loadData:data
						MIMEType:[response MIMEType]
		   characterEncodingName:[response textEncodingName]
						 baseURL:[response URL]];
	else
		nav = [_webView loadRequest:[NSURLRequest requestWithURL:dp.identifier.URL]];

	[_webView addObserver:self
			   forKeyPath:@"title"
				  options:NSKeyValueObservingOptionNew
				  context:nil];
	
	#if __has_feature(objc_arc)
	_navigation = nav;
	#else
	if(_navigation)
		[_navigation release];
	_navigation = [nav retain];
	#endif
#else
	_webView = [[WebView alloc] initWithFrame:NSZeroRect];
	[_webView setFrameLoadDelegate:self];
	WebPreferences *const prefs = [WebPreferences standardPreferences];
	[prefs setJavaEnabled:NO];
	[prefs setPlugInsEnabled:NO];
	[prefs setJavaScriptEnabled:NO];
	[prefs setJavaScriptCanOpenWindowsAutomatically:NO];
	[prefs setLoadsImagesAutomatically:NO];
	[_webView setPreferences:prefs];

	NSURLResponse *const response = [dp response];
	if(response)
		[_webView.mainFrame loadData:data
							MIMEType:[response MIMEType]
					textEncodingName:[response textEncodingName]
							 baseURL:[response URL]];
	else
		[_webView.mainFrame loadRequest:[NSURLRequest requestWithURL:dp.identifier.URL]];
#endif
}

- (void)read {}

//	MARK: - NSObject

- (void)dealloc
{
	[self _clearWebView];
#if !__has_feature(objc_arc)
	[super dealloc];
#endif
}

#if 1

- (void)observeValueForKeyPath:(NSString *)keyPath
					  ofObject:(id)object
						change:(NSDictionary<NSKeyValueChangeKey, id> *)change
					   context:(void *)context {
	if([keyPath isEqual:@"title"]) {
		WKWebView* webView = (WKWebView*) object;
		NSParameterAssert([webView isKindOfClass:[WKWebView class]]);
		[self.node.identifier setCustomDisplayName:webView.title];
	}
}

//	MARK: - id<WKNavigationDelegate>

- (void)				 webView:(WKWebView *)webView
	didFailProvisionalNavigation:(null_unspecified WKNavigation *)navigation
					   withError:(NSError *)error {
	[self webView:webView didFailNavigation:navigation withError:error];
}

- (void)	  webView:(WKWebView *)webView
	didFailNavigation:(WKNavigation *)navigation
			withError:(NSError *)error {
	if(navigation != _navigation)
		return;

	[self _clearWebView];
	[self setError:error];
	[[self node] loadFinishedForAdapter:self];
}

- (void)		webView:(WKWebView *)webView
	didFinishNavigation:(WKNavigation *)navigation {
	if(navigation != _navigation)
		return;

	/*	<https://stackoverflow.com/questions/34602662/accessing-dom-element-in-wkwebview>

	"WebView and WKWebView are not the same. The latter is faster and more secure but not as manipulable.
	
	For WKWebView, you'd want to use wkwebview.evaluateJavaScript to send a whole string of code that does
	the manipulations to the DOM. The completionHandler can asynchronously receive simple results like
	strings and numbers and fire off more JS evaluations based on those, but you can't receive DOM element
	references and directly tweak their properties from Swift."
	 */
/*	DOMHTMLDocument *const doc = [[(DOMHTMLDocument *)[frame DOMDocument] retain] autorelease];
	if([doc isKindOfClass:[DOMHTMLDocument class]]) {
		NSMutableArray *const providers = [NSMutableArray array];
		[providers addObjectsFromArray:[doc PG_providersForLinksWithMIMETypes:[PGResourceAdapter supportedMIMETypes]]];
		[providers addObjectsFromArray:[doc PG_providersForAnchorsWithSchemes:[NSArray arrayWithObjects:@"http", @"https", nil]]];
		[providers addObjectsFromArray:[doc PG_providersForImages]];
		NSMutableArray *const pages = [NSMutableArray array];
		for(PGDataProvider *const provider in providers) {
			PGNode *const node = [[[PGNode alloc] initWithParent:self identifier:[[provider identifier] displayableIdentifier]] autorelease];
			if(!node) continue;
			[node setDataProvider:provider];
			[pages addObject:node];
		}
		[self setUnsortedChildren:pages presortedOrder:PGSortInnateOrder];
		[[self node] loadFinishedForAdapter:self];
	} else {
		[[self node] fallbackFromFailedAdapter:self];
	}
	[self _clearWebView];	*/
}

#else

//	MARK: - NSObject(WebFrameLoadDelegate)

- (void)webView:(WebView *)sender didFailProvisionalLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
	[self webView:sender didFailLoadWithError:error forFrame:frame];
}
- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
	if(frame != [_webView mainFrame]) return;
	[self _clearWebView];
	[self setError:error];
	[[self node] loadFinishedForAdapter:self];
}

- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
	if(frame != [_webView mainFrame]) return;
	[[[self node] identifier] setCustomDisplayName:title];
}
- (void)webView:(WebView *)sender didReceiveIcon:(NSImage *)image forFrame:(WebFrame *)frame
{
	if(frame != [_webView mainFrame]) return;
	[[[self node] identifier] setIcon:image];
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	if(frame != [_webView mainFrame]) return;
	DOMHTMLDocument *const doc = [[(DOMHTMLDocument *)[frame DOMDocument] retain] autorelease];
	if([doc isKindOfClass:[DOMHTMLDocument class]]) {
		NSMutableArray *const providers = [NSMutableArray array];
		[providers addObjectsFromArray:[doc PG_providersForLinksWithMIMETypes:[PGResourceAdapter supportedMIMETypes]]];
		[providers addObjectsFromArray:[doc PG_providersForAnchorsWithSchemes:[NSArray arrayWithObjects:@"http", @"https", nil]]];
		[providers addObjectsFromArray:[doc PG_providersForImages]];
		NSMutableArray *const pages = [NSMutableArray array];
		for(PGDataProvider *const provider in providers) {
			PGNode *const node = [[[PGNode alloc] initWithParent:self identifier:[[provider identifier] displayableIdentifier]] autorelease];
			if(!node) continue;
			[node setDataProvider:provider];
			[pages addObject:node];
		}
		[self setUnsortedChildren:pages presortedOrder:PGSortInnateOrder];
		[[self node] loadFinishedForAdapter:self];
	} else {
		[[self node] fallbackFromFailedAdapter:self];
	}
	[self _clearWebView];
}

#endif

@end

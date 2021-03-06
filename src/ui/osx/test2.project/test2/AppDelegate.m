//
//  AppDelegate.m
//  test2
//
//  Created by Alari on 9/15/13.
//  Copyright (c) 2013 TogglDesktop developers. All rights reserved.
//

#import "AppDelegate.h"
#import "kopsik_api.h"
#import "Core.h"
#import "MainWindowController.h"
#import "PreferencesWindowController.h"
#import "Bugsnag.h"
#import "UIEvents.h"
#import "TimeEntryViewItem.h"
#import "AboutWindowController.h"
#import "ErrorHandler.h"
#import "ModelChange.h"
#import "MenuItemTags.h"
#import "User.h"
#import "Update.h"
#import "idler.h"
#import "IdleEvent.h"
#import "IdleNotificationWindowController.h"
#import "CrashReporter.h"
#import "FeedbackWindowController.h"
#import "const.h"
#import "EditNotification.h"
#import "MASShortcut+UserDefaults.h"

@interface AppDelegate()
@property (nonatomic, strong) IBOutlet MainWindowController *mainWindowController;
@property (nonatomic, strong) IBOutlet PreferencesWindowController *preferencesWindowController;
@property (nonatomic, strong) IBOutlet AboutWindowController *aboutWindowController;
@property (nonatomic, strong) IBOutlet IdleNotificationWindowController *idleNotificationWindowController;
@property (nonatomic, strong) IBOutlet FeedbackWindowController *feedbackWindowController;
@property TimeEntryViewItem *lastKnownRunningTimeEntry;
@property NSTimer *menubarTimer;
@property NSTimer *idleTimer;
@property NSString *lastKnownLoginState;
@property NSString *lastKnownTrackingState;
@property long lastIdleSecondsReading;
@property NSDate *lastIdleStarted;

// we'll be updating running TE as a menu item, too
@property (strong) IBOutlet NSMenuItem *runningTimeEntryMenuItem;

// Where logs are written and db is kept
@property NSString *app_path;
@property NSString *db_path;
@property NSString *log_path;
@property NSString *log_level;

// Environment (development, production, etc)
@property NSString *environment;

// Websocket and API hosts can be overriden
@property NSString *websocket_url_override;
@property NSString *api_url_override;

// For testing crash reporter
@property BOOL forceCrash;

// Avoid showing multiple upgrade dialogs
@property BOOL upgradeDialogVisible;

@property BOOL willTerminate;

@end

@implementation AppDelegate

void *ctx;
const int kDurationStringLength = 20;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
  NSLog(@"applicationDidFinishLaunching");

  self.willTerminate = NO;
  
  if (![self.environment isEqualToString:@"production"]) {
    // Turn on UI constraint debugging, if not in production
    [[NSUserDefaults standardUserDefaults] setBool:YES
                                            forKey:@"NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints"];
  }
  
  self.mainWindowController =
  [[MainWindowController alloc]
   initWithWindowNibName:@"MainWindowController"];
  [self.mainWindowController.window setReleasedWhenClosed:NO];
  
  PLCrashReporter *crashReporter = [self configuredCrashReporter];
  
  // Check if we previously crashed
  if ([crashReporter hasPendingCrashReport]) {
    [self handleCrashReport];
  }
  
  // Enable the Crash Reporter
  NSError *error;
  if (![crashReporter enableCrashReporterAndReturnError: &error]) {
    NSLog(@"Warning: Could not enable crash reporter: %@", error);
  }
  
  if (self.forceCrash) {
    abort();
  }

  if (!wasLaunchedAsHiddenLoginItem()) {
    [self onShowMenuItem:self];
  }
  
  self.inactiveAppIcon = [NSImage imageNamed:@"app_inactive"];
  
  self.preferencesWindowController = [[PreferencesWindowController alloc] initWithWindowNibName:@"PreferencesWindowController"];

  self.aboutWindowController = [[AboutWindowController alloc] initWithWindowNibName:@"AboutWindowController"];
  
  self.idleNotificationWindowController = [[IdleNotificationWindowController alloc] initWithWindowNibName:@"IdleNotificationWindowController"];
  
  self.feedbackWindowController = [[FeedbackWindowController alloc] initWithWindowNibName:@"FeedbackWindowController"];
  
  [self createStatusItem];
  
  [self applySettings];
  
  self.lastKnownLoginState = kUIStateUserLoggedOut;
  self.lastKnownTrackingState = kUIStateTimerStopped;
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateUserLoggedIn
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateUserLoggedOut
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateTimerRunning
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateTimerStopped
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUICommandShowPreferences
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIEventModelChange
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUICommandStopAt
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUICommandStop
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUICommandNew
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUICommandContinue
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIEventSettingsChanged
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateOffline
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateOnline
                                             object:nil];
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(eventHandler:)
                                               name:kUIStateUpdateAvailable
                                             object:nil];
  
  kopsik_context_start_events(ctx);
  
  NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
  NSNumber* checkEnabled = infoDict[@"KopsikCheckForUpdates"];
  if ([checkEnabled boolValue]) {
    [self checkForUpdates];
  }
  
  [MASShortcut registerGlobalShortcutWithUserDefaultsKey:kPreferenceGlobalShortcutShowHide handler:^{
    if ([self.mainWindowController.window isVisible]) {
      [self.mainWindowController.window close];
    } else {
      [self onShowMenuItem:self];
    }
  }];
  
  [MASShortcut registerGlobalShortcutWithUserDefaultsKey:kPreferenceGlobalShortcutStartStop handler:^{
    if ([self.lastKnownTrackingState isEqualTo:kUIStateTimerStopped]) {
      [self onNewMenuItem:self];
    } else {
      [self onStopMenuItem:self];
    }
  }];

  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
          selector: @selector(receiveSleepNote:)
          name: NSWorkspaceWillSleepNotification object: NULL];

  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver: self
          selector: @selector(receiveWakeNote:)
          name: NSWorkspaceDidWakeNotification object: NULL];

  [[NSUserNotificationCenter defaultUserNotificationCenter] setDelegate:self];
}

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center
     shouldPresentNotification:(NSUserNotification *)notification {
  return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center
       didActivateNotification:(NSUserNotification *)notification {
  NSLog(@"didActivateNotification %@", notification);
  [self onShowMenuItem:self];
}

- (void) userNotificationCenter:(NSUserNotificationCenter *)center
         didDeliverNotification:(NSUserNotification *)notification {
  NSLog(@"didDeliverNotification %@", notification);
}

- (void) receiveSleepNote: (NSNotification*) note {
    NSLog(@"receiveSleepNote: %@", [note name]);
    kopsik_set_sleep(ctx);
}

- (void) receiveWakeNote: (NSNotification*) note {
    NSLog(@"receiveWakeNote: %@", [note name]);
    kopsik_set_wake(ctx);
}

- (void)startWebSocket {
  NSLog(@"startWebSocket");
  kopsik_websocket_switch(ctx, 1);
}

- (void)stopWebSocket {
  NSLog(@"stopWebSocket");
  kopsik_websocket_switch(ctx, 0);
}

- (void)startTimeline {
  NSLog(@"startTimeline");
  kopsik_timeline_switch(ctx, 1);
}

- (void)stopTimeline {
  NSLog(@"stopTimeline");
  kopsik_timeline_switch(ctx, 0);
}

- (void)startNewTimeEntry:(TimeEntryViewItem *)new_time_entry {
  NSAssert(new_time_entry != nil, @"new time entry details cannot be nil");
  if (!kopsik_start(ctx,
                    [new_time_entry.Description UTF8String],
                    [new_time_entry.duration UTF8String],
                    new_time_entry.TaskID,
                    new_time_entry.ProjectID)) {
    return;
  }
  
  [self onShowMenuItem:self];
}

- (void)continueTimeEntry:(NSString *)guid {
  if (guid == nil) {
    kopsik_continue_latest(ctx);
  } else {
    kopsik_continue(ctx, [guid UTF8String]);
  }
  
  [self onShowMenuItem:self];
}

- (void)stopTimeEntry {
  kopsik_stop(ctx);
  
  [self onShowMenuItem:self];
}

- (void)stopTimeEntryAfterIdle:(IdleEvent *)idleEvent {
  NSAssert(idleEvent != nil, @"idle event cannot be nil");
  NSLog(@"Idle event: %@", idleEvent);
  NSTimeInterval startedAt = [idleEvent.started timeIntervalSince1970];
  NSLog(@"Time entry stop at %f", startedAt);
  kopsik_stop_running_time_entry_at(ctx, startedAt);

  [self onShowMenuItem:self];
}

- (void)userLoggedIn:(User *)user {
  self.lastKnownLoginState = kUIStateUserLoggedIn;
  
  // Start syncing after a while.
  [self performSelector:@selector(startSync)
             withObject:nil
             afterDelay:0.5];
  [self performSelector:@selector(startWebSocket)
             withObject:nil
             afterDelay:0.5];
  [self performSelector:@selector(startTimeline)
             withObject:nil
             afterDelay:0.5];
  
  renderRunningTimeEntry();
}

- (void)userLoggedOut {
  self.lastKnownLoginState = kUIStateUserLoggedOut;
  self.lastKnownTrackingState = kUIStateTimerStopped;
  self.lastKnownRunningTimeEntry = nil;
  [self stopWebSocket];
  [self stopTimeline];

  if (!self.willTerminate) {
    [NSApp setApplicationIconImage: self.inactiveAppIcon];
  }
}

- (void)timerStopped {
  self.lastKnownRunningTimeEntry = nil;
  self.lastKnownTrackingState = kUIStateTimerStopped;
  
  if (!self.willTerminate) {
    [NSApp setApplicationIconImage: self.inactiveAppIcon];
  }
}

- (void)timerStarted:(TimeEntryViewItem *)timeEntry {
  self.lastKnownRunningTimeEntry = timeEntry;
  self.lastKnownTrackingState = kUIStateTimerRunning;
  
  // Change app dock icon to default, which is red / tracking
  // See https://developer.apple.com/library/mac/documentation/Carbon/Conceptual/customizing_docktile/dockconcepts.pdf
  if (!self.willTerminate) {
    [NSApp setApplicationIconImage: nil];
  }
}

- (void)modelChanged:(ModelChange *)modelChange {
  if (self.lastKnownRunningTimeEntry &&
      [self.lastKnownRunningTimeEntry.GUID isEqualToString:modelChange.GUID] &&
      [modelChange.ModelType isEqualToString:@"time_entry"] &&
      [modelChange.ChangeType isEqualToString:@"update"]) {
    // Time entry duration can be edited on server side and it's
    // pushed to us via websocket or pulled via regular sync.
    // When it happens, timer keeps on running, but the time should be
    // updated on status item:
    self.lastKnownRunningTimeEntry = [TimeEntryViewItem findByGUID:modelChange.GUID];
  }
}

- (void)eventHandler: (NSNotification *) notification {
  if ([notification.name isEqualToString:kUIEventSettingsChanged]) {
    [self applySettings];
  } else if ([notification.name isEqualToString:kUICommandShowPreferences]) {
    [self onPreferencesMenuItem:self];
  } else if ([notification.name isEqualToString:kUICommandNew]) {
    [self startNewTimeEntry:notification.object];
  } else if ([notification.name isEqualToString:kUICommandContinue]) {
    [self continueTimeEntry:notification.object];
  } else if ([notification.name isEqualToString:kUICommandStop]) {
    [self stopTimeEntry];
  } else if ([notification.name isEqualToString:kUIStateUserLoggedIn]) {
    [self userLoggedIn:notification.object];
  } else if ([notification.name isEqualToString:kUIStateUserLoggedOut]) {
    [self userLoggedOut];
  } else if ([notification.name isEqualToString:kUIStateTimerStopped]) {
    [self timerStopped];
  } else if ([notification.name isEqualToString:kUIStateTimerRunning]) {
    [self timerStarted:notification.object];
  } else if ([notification.name isEqualToString:kUIEventModelChange]) {
    [self modelChanged:notification.object];
  } else if ([notification.name isEqualToString:kUICommandStopAt]) {
    [self stopTimeEntryAfterIdle:notification.object];
  } else if ([notification.name isEqualToString:kUIStateOffline]) {
    [self offlineMode:true];
  } else if ([notification.name isEqualToString:kUIStateOnline]) {
    [self offlineMode:false];
  } else if ([notification.name isEqualToString:kUIStateUpdateAvailable]) {
    [self performSelectorOnMainThread:@selector(presentUpgradeDialog:)
                           withObject:notification.object waitUntilDone:NO];
  }
  [self updateStatus];
}

- (void)offlineMode:(bool)offline {
  if (offline){
    self.currentOnImage = self.offlineOnImage;
    self.currentOffImage = self.offlineOffImage;
  } else {
    self.currentOnImage = self.onImage;
    self.currentOffImage = self.offImage;
  }
}

- (void)updateStatus {
  if (self.lastKnownRunningTimeEntry == nil) {
    [self.statusItem setTitle:@""];
    [self.statusItem setImage:self.currentOffImage];
    [self.runningTimeEntryMenuItem setTitle:@"Timer is not running."];
    return;
  }
  
  [self.statusItem setImage:self.currentOnImage];
  NSString *msg = [NSString stringWithFormat:@"Running: %@",
                   self.lastKnownRunningTimeEntry.Description];
  [self.runningTimeEntryMenuItem setTitle:msg];
}

- (void)createStatusItem {
  NSMenu *menu = [[NSMenu alloc] init];
  self.runningTimeEntryMenuItem = [menu addItemWithTitle:@"Timer status"
                                                  action:nil
                                           keyEquivalent:@""];
  [menu addItem:[NSMenuItem separatorItem]];
  [menu addItemWithTitle:@"New"
                  action:@selector(onNewMenuItem:)
           keyEquivalent:@"n"].tag = kMenuItemTagNew;
  [menu addItemWithTitle:@"Continue"
                  action:@selector(onContinueMenuItem:)
           keyEquivalent:@"o"].tag = kMenuItemTagContinue;
  [menu addItemWithTitle:@"Stop"
                  action:@selector(onStopMenuItem:)
           keyEquivalent:@"s"].tag = kMenuItemTagStop;
  [menu addItem:[NSMenuItem separatorItem]];
  [menu addItemWithTitle:@"Show"
                  action:@selector(onShowMenuItem:)
           keyEquivalent:@"t"];
  [menu addItem:[NSMenuItem separatorItem]];
  [menu addItemWithTitle:@"Sync"
                  action:@selector(onSyncMenuItem:)
           keyEquivalent:@""].tag = kMenuItemTagSync;
  [menu addItemWithTitle:@"Open in browser"
                  action:@selector(onOpenBrowserMenuItem:)
           keyEquivalent:@""].tag = kMenuItemTagOpenBrowser;
  [menu addItemWithTitle:@"Preferences"
                  action:@selector(onPreferencesMenuItem:)
           keyEquivalent:@""];
  [menu addItem:[NSMenuItem separatorItem]];
  [menu addItemWithTitle:@"About"
                  action:@selector(onAboutMenuItem:)
           keyEquivalent:@""];
  NSMenuItem *sendFeedbackMenuItem = [menu addItemWithTitle:@"Send Feedback"
                                                     action:@selector(onSendFeedbackMenuItem)
                                              keyEquivalent:@""];
  sendFeedbackMenuItem.tag = kMenuItemTagSendFeedback;
  [menu addItemWithTitle:@"Logout"
                  action:@selector(onLogoutMenuItem:)
           keyEquivalent:@""].tag = kMenuItemTagLogout;;
  [menu addItemWithTitle:@"Quit"
                  action:@selector(onQuitMenuItem)
           keyEquivalent:@""];
  
  NSStatusBar *bar = [NSStatusBar systemStatusBar];
  
  self.onImage = [NSImage imageNamed:@"on"];
  self.offImage = [NSImage imageNamed:@"off"];
  
  self.offlineOnImage = [NSImage imageNamed:@"offline_on"];
  self.offlineOffImage = [NSImage imageNamed:@"offline_off"];
  
  self.currentOnImage = self.onImage;
  self.currentOffImage = self.offImage;
  
  self.statusItem = [bar statusItemWithLength:NSVariableStatusItemLength];
  [self.statusItem setTitle:@""];
  [self.statusItem setHighlightMode:YES];
  [self.statusItem setEnabled:YES];
  [self.statusItem setMenu:menu];
  [self.statusItem setImage:self.currentOffImage];
}

- (void)applySettings {
  _Bool use_idle_detection = false;
  _Bool menubar_timer = false;
  _Bool dock_icon = false;
  _Bool on_top = false;
  _Bool reminder = false;
  if (!kopsik_get_settings(ctx,
                           &use_idle_detection,
                           &menubar_timer,
                           &dock_icon,
                           &on_top,
                           &reminder)) {
    return;
  }
  
  // Start idle detection, if its enabled
  if (use_idle_detection) {
    NSLog(@"Starting idle detection");
    self.idleTimer = [NSTimer
                      scheduledTimerWithTimeInterval:1.0
                      target:self
                      selector:@selector(idleTimerFired:)
                      userInfo:nil
                      repeats:YES];
  } else {
    NSLog(@"Idle detection is disabled. Stopping idle detection.");
    if (self.idleTimer != nil) {
      [self.idleTimer invalidate];
      self.idleTimer = nil;
    }
    [self.statusItem setTitle:@""];
  }
  
  // Start menubar timer if its enabled
  if (menubar_timer) {
    NSLog(@"Starting menubar timer");
    self.menubarTimer = [NSTimer
                         scheduledTimerWithTimeInterval:1.0
                         target:self
                         selector:@selector(menubarTimerFired:)
                         userInfo:nil
                         repeats:YES];
  } else {
    NSLog(@"Menubar timer is disabled. Stopping menubar timer.");
    if (self.menubarTimer != nil) {
      [self.menubarTimer invalidate];
      self.menubarTimer = nil;
    }
    [self.statusItem setTitle:@""];
  }
  
  // Show/Hide dock icon
  ProcessSerialNumber psn = { 0, kCurrentProcess };
  if (dock_icon) {
    NSLog(@"Showing dock icon");
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
  } else {
    NSLog(@"Hiding dock icon.");
    TransformProcessType(&psn, kProcessTransformToUIElementApplication);
  }
  
  // Stay on top
  if (on_top) {
    [self.mainWindowController.window setLevel:NSFloatingWindowLevel];
  } else {
    [self.mainWindowController.window setLevel:NSNormalWindowLevel];
  }
}

- (void)onNewMenuItem:(id)sender {
  [[NSNotificationCenter defaultCenter]
   postNotificationName:kUICommandNew
   object:[[TimeEntryViewItem alloc] init]];
}

- (void)onSendFeedbackMenuItem {
  [self.feedbackWindowController showWindow:self];
  [NSApp activateIgnoringOtherApps:YES];
}

- (void)onSendFeedbackMainMenuItem:(id)sender {
  [self onSendFeedbackMenuItem];
}

- (IBAction)onContinueMenuItem:(id)sender {
  [[NSNotificationCenter defaultCenter] postNotificationName:kUICommandContinue
                                                      object:nil];
}

- (IBAction)onStopMenuItem:(id)sender {
  [[NSNotificationCenter defaultCenter] postNotificationName:kUICommandStop
                                                      object:nil];
}

- (IBAction)onSyncMenuItem:(id)sender {
  [self startSync];
}

- (IBAction)onOpenBrowserMenuItem:(id)sender {
  NSString *togglWebsiteURL = [NSString stringWithUTF8String:kTogglWebsiteURL];
  [[NSWorkspace sharedWorkspace] openURL:
   [NSURL URLWithString:togglWebsiteURL]];
}

- (IBAction)onHelpMenuItem:(id)sender {
  NSString *supportURL = [NSString stringWithUTF8String:kSupportURL];
  [[NSWorkspace sharedWorkspace] openURL:
   [NSURL URLWithString:supportURL]];
}

- (IBAction)onLogoutMenuItem:(id)sender {
  kopsik_logout(ctx);
  [self onShowMenuItem:self];
}

- (IBAction)onClearCacheMenuItem:(id)sender {
  NSAlert *alert = [[NSAlert alloc] init];
  [alert addButtonWithTitle:@"OK"];
  [alert addButtonWithTitle:@"Cancel"];
  [alert setMessageText:@"Clear local data and log out?"];
  [alert setInformativeText:@"Deleted unsynced time entries cannot be restored."];
  [alert setAlertStyle:NSWarningAlertStyle];
  if ([alert runModal] != NSAlertFirstButtonReturn) {
    return;
  }
  
  kopsik_clear_cache(ctx);
}

- (IBAction)onAboutMenuItem:(id)sender {
  [self.aboutWindowController showWindow:self];
  [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)onShowMenuItem:(id)sender {
  [self.mainWindowController showWindow:self];
  [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)onPreferencesMenuItem:(id)sender {
  [self.preferencesWindowController showWindow:self];
  [NSApp activateIgnoringOtherApps:YES];
}

- (IBAction)onHideMenuItem:(id)sender {
  [self.mainWindowController.window close];
}

- (void)onQuitMenuItem {
  [[NSApplication sharedApplication] terminate:self];
}

- (void)applicationWillTerminate:(NSNotification *)app {
  NSLog(@"applicationWillTerminate");
  self.willTerminate = YES;
  kopsik_context_clear(ctx);
  ctx = 0;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender
                    hasVisibleWindows:(BOOL)flag{
  [self.mainWindowController.window setIsVisible:YES];
  return YES;
}

- (NSString *)applicationSupportDirectory {
  NSString *path;
  NSError *error;
  NSArray* paths = NSSearchPathForDirectoriesInDomains(
                                                       NSApplicationSupportDirectory, NSUserDomainMask, YES);
  if ([paths count] == 0) {
    NSLog(@"Unable to access application support directory!");
  }
  path = [paths[0] stringByAppendingPathComponent:@"Kopsik"];
  
  // Append environment name to path. So we can have
  // production and development running side by side.
  path = [path stringByAppendingPathComponent:self.environment];
  
	if ([[NSFileManager defaultManager] fileExistsAtPath:path]){
    return path;
  }
	if (![[NSFileManager defaultManager] createDirectoryAtPath:path
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:&error]){
		NSLog(@"Create directory error: %@", error);
	}
  return path;
}

const NSString *appName = @"osx_native_app";

- (void)parseCommandLineArguments{
  NSArray *arguments = [[NSProcessInfo processInfo] arguments];
  NSLog(@"Command line arguments: %@", arguments);
  
  for (int i = 1; i < arguments.count; i++) {
    NSString *argument = arguments[i];
    
    if (([argument rangeOfString:@"force"].location != NSNotFound) &&
        ([argument rangeOfString:@"crash"].location != NSNotFound)) {
      NSLog(@"forcing crash");
      self.forceCrash = YES;
      continue;
    }
    if (([argument rangeOfString:@"log"].location != NSNotFound) &&
        ([argument rangeOfString:@"path"].location != NSNotFound)) {
      self.log_path = arguments[i+1];
      NSLog(@"log path overriden with '%@'", self.log_path);
      continue;
    }
    if (([argument rangeOfString:@"db"].location != NSNotFound) &&
        ([argument rangeOfString:@"path"].location != NSNotFound)) {
      self.db_path = arguments[i+1];
      NSLog(@"db path overriden with '%@'", self.db_path);
      continue;
    }
    if (([argument rangeOfString:@"log"].location != NSNotFound) &&
        ([argument rangeOfString:@"level"].location != NSNotFound)) {
      self.log_level = arguments[i+1];
      NSLog(@"log level overriden with '%@'", self.log_level);
      continue;
    }
    if (([argument rangeOfString:@"api"].location != NSNotFound) &&
        ([argument rangeOfString:@"url"].location != NSNotFound)) {
      self.api_url_override = arguments[i+1];
      NSLog(@"API URL overriden with '%@'", self.api_url_override);
      continue;
    }
    if (([argument rangeOfString:@"websocket"].location != NSNotFound) &&
        ([argument rangeOfString:@"url"].location != NSNotFound)) {
      self.websocket_url_override = arguments[i+1];
      NSLog(@"Websocket URL overriden with '%@'", self.websocket_url_override);
      continue;
    }
  }
}

- (void)disallowDuplicateInstances {
  // Disallow duplicate instances in production
  if (![self.environment isEqualToString:@"production"]) {
    return;
  }
  if ([[NSRunningApplication runningApplicationsWithBundleIdentifier:
        [[NSBundle mainBundle] bundleIdentifier]] count] > 1) {
    NSString *msg = [NSString
                     stringWithFormat:@"Another copy of %@ is already running.",
                     [[NSBundle mainBundle]
                      objectForInfoDictionaryKey:(NSString *)kCFBundleNameKey]];
    [[NSAlert alertWithMessageText:msg
                     defaultButton:nil
                   alternateButton:nil
                       otherButton:nil
         informativeTextWithFormat:@"This copy will now quit."] runModal];
    
    [NSApp terminate:nil];
  }
}

- (id) init {
  self = [super init];
  
  NSDictionary* infoDict = [[NSBundle mainBundle] infoDictionary];
  self.environment = infoDict[@"KopsikEnvironment"];
  
  [self disallowDuplicateInstances];
  
  [Bugsnag startBugsnagWithApiKey:@"2a46aa1157256f759053289f2d687c2f"];
  NSAssert(self.environment != nil, @"Missing environment in plist");
  [Bugsnag configuration].releaseStage = self.environment;
  
  self.app_path = [self applicationSupportDirectory];
  self.db_path = [self.app_path stringByAppendingPathComponent:@"kopsik.db"];
  self.log_path = [self.app_path stringByAppendingPathComponent:@"kopsik.log"];
  self.log_level = @"debug";
  
  [self parseCommandLineArguments];
  
  NSLog(@"Starting with db path %@, log path %@, log level %@",
        self.db_path, self.log_path, self.log_level);
  
  kopsik_set_log_path([self.log_path UTF8String]);
  kopsik_set_log_level([self.log_level UTF8String]);
  
  NSString* version = infoDict[@"CFBundleShortVersionString"];
  
  ctx = kopsik_context_init([appName UTF8String], [version UTF8String]);
  
  kopsik_context_set_view_item_change_callback(ctx, on_model_change_callback);
  kopsik_context_set_error_callback(ctx, handle_error);
  kopsik_context_set_check_update_callback(ctx, on_update_checked);
  kopsik_context_set_online_callback(ctx, on_online);
  kopsik_context_set_user_login_callback(ctx, on_user_login);
  kopsik_set_open_url_callback(ctx, on_open_url);
  kopsik_set_remind_callback(ctx, on_remind);
                            
  NSLog(@"Version %@", version);
  
  _Bool res = kopsik_set_db_path(ctx, [self.db_path UTF8String]);
  NSAssert(res,
           ([NSString stringWithFormat:@"Failed to initialize DB with path: %@", self.db_path]));
  
  id logToFile = infoDict[@"KopsikLogUserInterfaceToFile"];
  if ([logToFile boolValue]) {
    NSLog(@"Redirecting UI log to file");
    NSString *logPath =
    [self.app_path stringByAppendingPathComponent:@"ui.log"];
    freopen([logPath fileSystemRepresentation],"a+", stderr);
  }
  
  res = kopsik_configure_proxy(ctx);
  NSAssert(res, @"Failed to initialize DB");
  
  if (self.api_url_override != nil) {
    kopsik_set_api_url(ctx, [self.api_url_override UTF8String]);
  }
  
  if (self.websocket_url_override != nil) {
    kopsik_set_websocket_url(ctx, [self.websocket_url_override UTF8String]);
  }
  
  NSLog(@"AppDelegate init done");
  
  return self;
}

- (void)menubarTimerFired:(NSTimer*)timer {
  if (self.lastKnownRunningTimeEntry != nil) {
    char str[kDurationStringLength];
    kopsik_format_duration_in_seconds_hhmm(
                                           self.lastKnownRunningTimeEntry.duration_in_seconds,
                                           str,
                                           kDurationStringLength);
    NSString *statusStr = @" ";
    statusStr = [statusStr stringByAppendingString:[NSString stringWithUTF8String:str]];
    [self.statusItem setTitle:statusStr];
  }
}

- (void)idleTimerFired:(NSTimer*)timer {
  uint64_t idle_seconds = 0;
  if (0 != get_idle_time(&idle_seconds)) {
    NSLog(@"Achtung! Failed to get idle status.");
    return;
  }
  
  //  NSLog(@"Idle seconds: %lld", idle_seconds);
  
  if (idle_seconds >= kIdleThresholdSeconds && self.lastIdleStarted == nil) {
    NSTimeInterval since = [[NSDate date] timeIntervalSince1970] - idle_seconds;
    self.lastIdleStarted = [NSDate dateWithTimeIntervalSince1970:since];
    NSLog(@"User is idle since %@", self.lastIdleStarted);
    
  } else if (self.lastIdleStarted != nil &&
             self.lastIdleSecondsReading >= idle_seconds) {
    NSDate *now = [NSDate date];
    if (self.lastKnownRunningTimeEntry) {
      IdleEvent *idleEvent = [[IdleEvent alloc] init];
      idleEvent.started = self.lastIdleStarted;
      idleEvent.finished = now;
      idleEvent.seconds = self.lastIdleSecondsReading;
      [[NSNotificationCenter defaultCenter]
       postNotificationName:kUIEventIdleFinished
       object:idleEvent];
    } else {
      NSLog(@"Time entry is not running, ignoring idleness");
    }
    NSLog(@"User is not idle since %@", now);
    self.lastIdleStarted = nil;
  }
  
  self.lastIdleSecondsReading = idle_seconds;
}

- (BOOL)validateUserInterfaceItem:(id<NSValidatedUserInterfaceItem>)anItem {
  switch ([anItem tag]) {
    case kMenuItemTagNew:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      break;
    case kMenuItemTagContinue:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      if (self.lastKnownTrackingState != kUIStateTimerStopped) {
        return NO;
      }
      break;
    case kMenuItemTagStop:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      if (self.lastKnownTrackingState != kUIStateTimerRunning) {
        return NO;
      }
      break;
    case kMenuItemTagSync:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      break;
    case kMenuItemTagLogout:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      break;
    case kMenuItemTagClearCache:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      break;
    case kMenuItemTagSendFeedback:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      break;
    case kMenuItemTagOpenBrowser:
      if (self.lastKnownLoginState != kUIStateUserLoggedIn) {
        return NO;
      }
      break;
    default:
      // Dont care about this stuff
      break;
  }
  return YES;
}

void renderRunningTimeEntry() {
  KopsikTimeEntryViewItem *item = kopsik_time_entry_view_item_init();
  _Bool is_tracking = false;
  if (!kopsik_running_time_entry_view_item(ctx, item, &is_tracking)) {
    kopsik_time_entry_view_item_clear(item);
    return;
  }
  
  if (is_tracking) {
    TimeEntryViewItem *timeEntry = [[TimeEntryViewItem alloc] init];
    [timeEntry load:item];
    [[NSNotificationCenter defaultCenter]
     postNotificationName:kUIStateTimerRunning object:timeEntry];
  } else {
    [[NSNotificationCenter defaultCenter]
     postNotificationName:kUIStateTimerStopped object:nil];
  }
  kopsik_time_entry_view_item_clear(item);
}

// FIXME: delete
void on_model_change_callback(KopsikModelChange *change) {
  NSLog(@"on_model_change_callback %s %s ID=%llu GUID=%s in thread %@",
        change->ChangeType,
        change->ModelType,
        change->ModelID,
        change->GUID,
        [NSThread currentThread]);
  
  ModelChange *modelChange = [[ModelChange alloc] init];
  [modelChange load:change];
  
  [[NSNotificationCenter defaultCenter]
   postNotificationName:kUIEventModelChange object:modelChange];
}

- (void)startSync {
  NSLog(@"startSync");
  kopsik_sync(ctx);
}

- (void)checkForUpdates {
  kopsik_check_for_updates(ctx);
}

- (void)presentUpgradeDialog:(Update *)update {
  if (self.upgradeDialogVisible) {
    NSLog(@"Upgrade dialog already visible");
    return;
  }
  self.upgradeDialogVisible = YES;
  
  NSAlert *alert = [[NSAlert alloc] init];
  [alert addButtonWithTitle:@"Yes"];
  [alert addButtonWithTitle:@"No"];
  [alert setMessageText:@"Download new version?"];
  NSString *informative = [NSString stringWithFormat:
                           @"There's a new version of this app available (%@).", update.version];
  [alert setInformativeText:informative];
  [alert setAlertStyle:NSWarningAlertStyle];
  if ([alert runModal] != NSAlertFirstButtonReturn) {
    self.upgradeDialogVisible = NO;
    return;
  }
  
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:update.URL]];
  [NSApp terminate:nil];
}

- (PLCrashReporter *)configuredCrashReporter {
  PLCrashReporterConfig *config = [[PLCrashReporterConfig alloc]
                                   initWithSignalHandlerType:PLCrashReporterSignalHandlerTypeBSD
                                   symbolicationStrategy:PLCrashReporterSymbolicationStrategyAll];
  return [[PLCrashReporter alloc] initWithConfiguration: config];
}

- (void) handleCrashReport {
  PLCrashReporter *crashReporter = [self configuredCrashReporter];
  
  NSError *error;
  NSData *crashData = [crashReporter loadPendingCrashReportDataAndReturnError: &error];
  if (crashData == nil) {
    NSLog(@"Could not load crash report: %@", error);
    [crashReporter purgePendingCrashReport];
    return;
  }
  
  PLCrashReport *report = [[PLCrashReport alloc] initWithData: crashData
                                                        error: &error];
  if (report == nil) {
    NSLog(@"Could not parse crash report");
    [crashReporter purgePendingCrashReport];
    return;
  }
  
  NSString *summary = [NSString stringWithFormat:@"Crashed with signal %@ (code %@)",
                       report.signalInfo.name,
                       report.signalInfo.code];
  
  NSString *humanReadable = [PLCrashReportTextFormatter stringValueForCrashReport:report
                                                                   withTextFormat:PLCrashReportTextFormatiOS];
  NSLog(@"Crashed on %@", report.systemInfo.timestamp);
  NSLog(@"Report: %@", humanReadable);
  
  NSException* exception;
  NSMutableDictionary *data = [[NSMutableDictionary alloc] init];;
  if (report.hasExceptionInfo) {
    exception = [NSException
                 exceptionWithName:report.exceptionInfo.exceptionName
                 reason:report.exceptionInfo.exceptionReason
                 userInfo:nil];
  } else {
    exception = [NSException
                 exceptionWithName:summary
                 reason:humanReadable
                 userInfo:nil];
  }
  [Bugsnag notify:exception withData:data];
  
  [crashReporter purgePendingCrashReport];
}

void on_update_checked(
                                const _Bool is_update_available,
                                const char *url,
                                const char *version) {
  if (!is_update_available) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kUIStateUpToDate
                                                        object:nil];
    return;
  }
  Update *update = [[Update alloc] init];
  update.URL = [NSString stringWithUTF8String:url];
  update.version = [NSString stringWithUTF8String:version];
  [[NSNotificationCenter defaultCenter] postNotificationName:kUIStateUpdateAvailable
                                                      object:update];
}

void on_online() {
  [[NSNotificationCenter defaultCenter] postNotificationName:kUIStateOnline object:nil];
}

void on_user_login(const uint64_t user_id,
                            const char *fullname,
                            const char *timeofdayformat) {
  if (!user_id) {
    [[NSNotificationCenter defaultCenter] postNotificationName:kUIStateUserLoggedOut object:nil];
    return;
  }
  User *userinfo = [[User alloc] init];
  userinfo.ID = user_id;
  userinfo.fullname = [NSString stringWithUTF8String:fullname];
  userinfo.timeOfDayFormat = [NSString stringWithUTF8String:timeofdayformat];
  [[NSNotificationCenter defaultCenter] postNotificationName:kUIStateUserLoggedIn object:userinfo];
}

void on_remind() {
  NSUserNotification *notification = [[NSUserNotification alloc] init];
  [notification setTitle:@"Reminder from Toggl Desktop"];
  [notification setInformativeText:@"Shouldn't you be tracking?"];
  [notification setDeliveryDate:[NSDate dateWithTimeInterval:0 sinceDate:[NSDate date]]];
  [notification setSoundName:NSUserNotificationDefaultSoundName];
  NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
  [center scheduleNotification:notification];
}

void on_open_url(const char *url) {
  [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:[NSString stringWithUTF8String:url]]];
}

// See https://codereview.chromium.org/7497056/patch/2002/4002 for inspiration
BOOL wasLaunchedAsLoginOrResumeItem() {
  ProcessSerialNumber psn = {0, kCurrentProcess};
  NSDictionary *process_info = (__bridge NSDictionary *)ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);

  long long temp = [[process_info objectForKey:@"ParentPSN"] longLongValue];
  ProcessSerialNumber parent_psn = {(temp >> 32) & 0x00000000FFFFFFFFLL, temp & 0x00000000FFFFFFFFLL};

  NSDictionary *parent_info = (__bridge NSDictionary *)ProcessInformationCopyDictionary(&parent_psn,
                                                               kProcessDictionaryIncludeAllInformationMask);

  return [[parent_info objectForKey:@"FileCreator"] isEqualToString:@"lgnw"];
}

// See https://codereview.chromium.org/7497056/patch/2002/4002 for inspiration
BOOL wasLaunchedAsHiddenLoginItem() {
  if (!wasLaunchedAsLoginOrResumeItem()) {
    return NO;
  }

  LSSharedFileListRef login_items = LSSharedFileListCreate(NULL,
                                                           kLSSharedFileListSessionLoginItems,
                                                           NULL);

  if (!login_items) {
    return NO;
  }

  CFArrayRef login_items_array = LSSharedFileListCopySnapshot(login_items,
                                                              NULL);

  CFURLRef url_ref = (__bridge CFURLRef)[NSURL fileURLWithPath:[[NSBundle mainBundle] bundlePath]];

  for (int i = 0 ; i < CFArrayGetCount(login_items_array); i++) {
    LSSharedFileListItemRef item = (LSSharedFileListItemRef)CFArrayGetValueAtIndex(login_items_array, i);
    CFURLRef item_url_ref = NULL;
    if (!LSSharedFileListItemResolve(item, 0, &item_url_ref, NULL) == noErr) {
      continue;
    }
    if (CFEqual(item_url_ref, url_ref)) {
      CFBooleanRef hidden = LSSharedFileListItemCopyProperty(item, kLSSharedFileListLoginItemHidden);
      return (hidden && kCFBooleanTrue == hidden);
    }
  }

  return NO;
}

@end

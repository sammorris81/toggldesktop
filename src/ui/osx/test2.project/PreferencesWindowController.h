//
//  PreferencesWindowController.h
//  Kopsik
//
//  Created by Tanel Lebedev on 22/10/2013.
//  Copyright (c) 2013 TogglDesktop developers. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "MASShortcutView+UserDefaults.h"

extern NSString *const kPreferenceGlobalShortcutShowHide;
extern NSString *const kPreferenceGlobalShortcutStartStop;

@interface PreferencesWindowController : NSWindowController
@property IBOutlet NSTextField *hostTextField;
@property IBOutlet NSTextField *portTextField;
@property IBOutlet NSTextField *usernameTextField;
@property IBOutlet NSTextField *passwordTextField;
@property IBOutlet NSButton *useProxyButton;
@property IBOutlet NSButton *useIdleDetectionButton;
@property IBOutlet NSButton *recordTimelineCheckbox;
@property IBOutlet NSButton *menubarTimerCheckbox;
@property IBOutlet NSButton *dockIconCheckbox;
@property IBOutlet NSButton *ontopCheckbox;
@property IBOutlet NSButton *reminderCheckbox;
@property IBOutlet MASShortcutView *showHideShortcutView;
@property IBOutlet MASShortcutView *startStopShortcutView;
- (IBAction)useProxyButtonChanged:(id)sender;
- (IBAction)hostTextFieldChanged:(id)sender;
- (IBAction)portTextFieldChanged:(id)sender;
- (IBAction)usernameTextFieldChanged:(id)sender;
- (IBAction)passwordTextFieldChanged:(id)sender;
- (IBAction)useIdleDetectionButtonChanged:(id)sender;
- (IBAction)recordTimelineCheckboxChanged:(id)sender;
- (IBAction)menubarTimerCheckboxChanged:(id)sender;
- (IBAction)dockIconCheckboxChanged:(id)sender;
- (IBAction)ontopCheckboxChanged:(id)sender;
- (IBAction)reminderCheckboxChanged:(id)sender;
@end

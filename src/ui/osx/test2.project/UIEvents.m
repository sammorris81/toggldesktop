//
//  UIEvents.m
//  kopsik_ui_osx
//
//  Created by Tanel Lebedev on 24/09/2013.
//  Copyright (c) 2013 TogglDesktop developers. All rights reserved.
//

#import "UIEvents.h"

// States
NSString *const kUIStateUserLoggedIn = @"UserLoggedIn";
NSString *const kUIStateUserLoggedOut = @"UserLoggedOut";
NSString *const kUIStateTimerRunning = @"TimerRunning";
NSString *const kUIStateTimerStopped = @"TimerStopped";
NSString *const kUIStateTimeEntrySelected = @"TimeEntrySelected";
NSString *const kUIStateTimeEntryDeselected = @"TimeEntryDeselected";
NSString *const kUIStateError = @"Error";
NSString *const kUIStateUpdateAvailable = @"UpdateAvailable";
NSString *const kUIStateUpToDate = @"UpToDate";

// Events
NSString *const kUIEventModelChange = @"ModelChange";
NSString *const kUIEventIdleFinished = @"IdleFinished";
NSString *const kUIEventSettingsChanged = @"SettingsChanged";
NSString *const kUIEventShowListView = @"ShowListView";

// Commands
NSString *const kUICommandNew = @"New";
NSString *const kUICommandStop = @"Stop";
NSString *const kUICommandContinue = @"Continue";
NSString *const kUICommandShowPreferences = @"Show Preferences";
NSString *const kUICommandStopAt = @"Stop At";
NSString *const kUICommandEditRunningTimeEntry = @"Edit Running Time Entry";

NSString *const kUIDurationClicked = @"duration";
NSString *const kUIDescriptionClicked = @"description";

NSString *const kUIStateOffline = @"Offline";
NSString *const kUIStateOnline = @"Online";

float const kThrottleSeconds = 0.1;

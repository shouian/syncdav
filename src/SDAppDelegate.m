//
//  flysyncAppDelegate.m
//  flysync
//
//  Created by August Mueller on 5/24/11.
//  Copyright 2011 Flying Meat Inc. All rights reserved.
//

#import "SDAppDelegate.h"
#import "FMKeychainItem.h"
#import "FMNSStringAdditions.h"
#import "SDEchoReflector.h"

NSString *SDEncytionPhraseKeychainName = @"%@ SyncDAV Encryption Phrase";

@interface SDAppDelegate ()
- (void)startSyncManager;
- (void)makeLocalSyncFolderAtPath:(NSString*)path;
@end

@implementation SDAppDelegate

@synthesize window;

- (void)awakeFromNib {
	
    [window center];
    
    if ([FMPrefs objectForKey:@"localPath"]) {
        [localPathControl setURL:[NSURL fileURLWithPath:[FMPrefs objectForKey:@"localPath"]]];
    }
    else {
        
        NSString *localPath = [@"~/SyncDAV" stringByExpandingTildeInPath];
        
        [self makeLocalSyncFolderAtPath:localPath];
        
        [localPathControl setURL:[NSURL fileURLWithPath:localPath]];
        
    }
    
    if ([FMPrefs objectForKey:@"remoteURL"] && [FMPrefs objectForKey:@"username"]) {
        
        FMKeychainItem *k = [FMKeychainItem keychainItemWithService:[FMPrefs objectForKey:@"remoteURL"] forAccount:[FMPrefs objectForKey:@"username"]];
        
        NSString *pass = [k genericPassword];
        
        if (pass) {
            [passTextField setStringValue:pass];
        }
        
        
        NSString *phraseURL = [NSString stringWithFormat:SDEncytionPhraseKeychainName, [FMPrefs objectForKey:@"remoteURL"]];
        
        
        k = [FMKeychainItem keychainItemWithService:phraseURL forAccount:[FMPrefs objectForKey:@"username"]];
        
        if ((pass = [k genericPassword])) {
            [encryptionPhraseTextField setStringValue:pass];
        }
        
    }
    
    if (![FMPrefs objectForKey:@"remoteURL"]) {
        
        NSString *uname = [FMPrefs objectForKey:@"iToolsMember"];
        if (uname) {
            
            [userTextField setStringValue:uname];
            [urlTextField setStringValue:[NSString stringWithFormat:@"https://idisk.me.com/%@/SyncDAV/", uname]];
            
            FMKeychainItem *k   = [FMKeychainItem keychainItemWithService:@"iTools" forAccount:uname];

            if ([k genericPassword]) {
                [passTextField setStringValue:[k genericPassword]];
            }
        }
    }
}

- (void)makeLocalSyncFolderAtPath:(NSString*)localPath {
    
    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir;
    if (![fm fileExistsAtPath:localPath isDirectory:&isDir]) {
        
        NSError *outErr;
        if (![fm createDirectoryAtPath:localPath withIntermediateDirectories:YES attributes:nil error:&outErr]) {
            NSLog(@"Could not create %@", localPath);
            debug(@"outErr: '%@'", outErr);
        }
        else {
            [[NSWorkspace sharedWorkspace] setIcon:[NSImage imageNamed:@"SyncDAVFolderIcon"] forFile:localPath options:0];
        }
    }
}

- (void)stopPollingTimer {
    
}

- (void)startPollingTimer {
    
    if (_pollingTimer) {
        [_pollingTimer invalidate];
        [_pollingTimer release];
    }
    
    NSTimeInterval seconds = [FMPrefs floatForKey:@"pollTime"];
    
    if (seconds < 1) {
        // we've got it set to manual in this case.
        return;
    }
    
    _pollingTimer = [[NSTimer scheduledTimerWithTimeInterval:seconds * 60 target:self selector:@selector(pollingTimerHit:) userInfo:nil repeats:YES] retain];
}

- (void)pollingTimerHit:(NSTimer*)aNiceTimerToIgnore {
    [self syncAction:nil];
}

- (void)startSyncManager {
    
    NSURL *localURL  = [localPathControl URL];
    NSURL *remoteURL = [NSURL URLWithString:[urlTextField stringValue]];
    NSString *user   = [userTextField stringValue];
    
    if (!remoteURL) {
        [window makeFirstResponder:urlTextField];
        return;
    }
    
    if (!user) {
        [window makeFirstResponder:userTextField];
        return;
    }
    
    if (!localURL) {
        [self chooseLocalFolderAction:nil];
        return;
    }
    
    FMKeychainItem *k = [FMKeychainItem keychainItemWithService:[remoteURL absoluteString] forAccount:user];
    
    NSString *pass = [k genericPassword];
    
    if (!pass) {
        pass = [passTextField stringValue];
        
        if ([pass length]) {
            [k addGenericPassword:pass];
        }
        else {
            pass = 0x00;
        }
    }
    
    if (!pass) {
        [window makeFirstResponder:passTextField];
        return;
    }
    
    
    NSString *phraseURL = [NSString stringWithFormat:SDEncytionPhraseKeychainName, [FMPrefs objectForKey:@"remoteURL"]];
    FMKeychainItem *phraseKeychain = [FMKeychainItem keychainItemWithService:phraseURL forAccount:[FMPrefs objectForKey:@"username"]];
    
    NSString *encPhrase = [phraseKeychain genericPassword];
    
    if (!encPhrase && [[[encryptionPhraseTextField stringValue] trim] length]) {
        debug(@"Adding %@ to the keychain", encPhrase);
        [phraseKeychain addGenericPassword:[encryptionPhraseTextField stringValue]];
    }
    
    
    if (![pass isEqualTo:[passTextField stringValue]]) {
#pragma message "FIXME: cleanup password changes!"
        SDAssert(NO); // gus, fix this case. (password change)
    }
    
    if (encPhrase && ![encPhrase isEqualTo:[encryptionPhraseTextField stringValue]]) {
        #pragma message "FIXME: cleanup password changes!"
        SDAssert(NO); // gus, fix this case. (password change)
    }
    
    [self makeLocalSyncFolderAtPath:[localURL path]];
    
    
    FMRelease(_manager);
    _manager = [[SDManager managerWithLocalURL:localURL remoteURL:remoteURL username:user password:pass] retain];
    
    [progressSpinner startAnimation:nil];
    [statusTextField setStringValue:@"Authenticating…"];
    [syncButton setEnabled:NO];
    
    [_manager authenticateWithFinishBlock:^(NSError *err) {
        
        SDEchoReflector *ref = [SDEchoReflector reflectorWithHostname:@"zero.local" port:7000 password:@"password" manager:_manager];
        
        #pragma message "FIXME: check for an error here."
        [ref connect];
        
        [_manager setReflector:ref];
        
        
        [syncButton setEnabled:YES];
        [progressSpinner stopAnimation:nil];
        [statusTextField setStringValue:@""];
        
        if ([_manager authenticated]) {
            [statusTextField setStringValue:@"Performing full sync"];
            [progressSpinner startAnimation:nil];
            [_manager fullSyncWithFinishBlock:^(NSError *arg1) {
                [syncButton setTitle:@"Sync"];
                [progressSpinner stopAnimation:nil];
                [self startPollingTimer];
            }];
        }
        else {
            NSBeep();
            NSLog(@"Error authenticating!");
            NSLog(@"%@", err);
            FMRelease(_manager);
        }
        
    }];
    
    
    
}

- (void)syncAction:(id)sender {
    
    if (!_manager) {
        [self startSyncManager];
    }
    else if (![_manager authenticated]) {
        debug(@"Hold your horses- still authenticating.");
    }
    else {
        
        [progressSpinner startAnimation:nil];
        [statusTextField setStringValue:@"Syncing…"];
        
        [_manager fullSyncWithFinishBlock:^(NSError *arg1) {
            [progressSpinner stopAnimation:nil];
            [statusTextField setStringValue:@""];
        }];
    }
    
}

- (void)chooseLocalFolderAction:(id)sender {
    
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setAllowsMultipleSelection:NO];
    
    [panel setPrompt:@"Sync This Folder"];
    
    [panel beginSheetModalForWindow:window completionHandler:^(NSInteger result) {
        
        if (result == NSOKButton) {
            
            NSURL *u = [panel URL];
            
            [FMPrefs setObject:[u path] forKey:@"localPath"];
            [localPathControl setURL:u];
            
        }
        
    }];
}

- (void)sdDebugAction:(id)sender {
    
}

@end

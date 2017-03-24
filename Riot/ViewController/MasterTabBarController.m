/*
 Copyright 2017 Vector Creations Ltd
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "MasterTabBarController.h"

#import "UnifiedSearchViewController.h"

#import "RecentsDataSource.h"

#import "AppDelegate.h"

@interface MasterTabBarController ()
{
    // Array of `MXSession` instances.
    NSMutableArray *mxSessionArray;    
    
    // Tell whether the authentication screen is preparing.
    BOOL isAuthViewControllerPreparing;
    
    // Observer that checks when the Authentification view controller has gone.
    id authViewControllerObserver;
    
    // The parameters to pass to the Authentification view controller.
    NSDictionary *authViewControllerRegistrationParameters;
    
    RecentsDataSource *homeDataSource;
    
    // The current unified search screen if any
    UnifiedSearchViewController *unifiedSearchViewController;
    
    // Current alert (if any).
    MXKAlert *currentAlert;
}

@end

@implementation MasterTabBarController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    // Retrieve the home view controller
    _homeViewController = [self.viewControllers objectAtIndex:TABBAR_HOME_INDEX];
    
    // Initialize here the data sources if a matrix session has been already set.
    [self initializeDataSources];
    
    // Sanity check
    NSAssert(_homeViewController, @"Something wrong in Main.storyboard");
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    // Check whether we're not logged in
    if (![MXKAccountManager sharedManager].accounts.count)
    {
        [self showAuthenticationScreen];
    }
    else
    {
        // Check whether the user has been already prompted to send crash reports.
        // (Check whether 'enableCrashReport' flag has been set once)
        if (![[NSUserDefaults standardUserDefaults] objectForKey:@"enableCrashReport"])
        {
            [self promptUserBeforeUsingGoogleAnalytics];
        }
    }
    
    if (unifiedSearchViewController)
    {
        [unifiedSearchViewController destroy];
        unifiedSearchViewController = nil;
    }
}

- (void)dealloc
{
    mxSessionArray = nil;
    
    _homeViewController = nil;
    
    if (currentAlert)
    {
        [currentAlert dismiss:NO];
        currentAlert = nil;
    }
    
    if (authViewControllerObserver)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:authViewControllerObserver];
        authViewControllerObserver = nil;
    }
}

#pragma mark -

- (NSArray*)mxSessions
{
    return [NSArray arrayWithArray:mxSessionArray];
}

- (void)initializeDataSources
{
    MXSession *mainSession = mxSessionArray.firstObject;
    
    if (mainSession)
    {
        // Init the recents data source
        homeDataSource = [[RecentsDataSource alloc] initWithMatrixSession:mainSession];
        [_homeViewController displayList:homeDataSource];
        
        // Check whether there are others sessions
        NSArray* mxSessions = self.mxSessions;
        if (mxSessions.count > 1)
        {
            for (MXSession *mxSession in mxSessions)
            {
                if (mxSession != mainSession)
                {
                    // Add the session to the recents data source
                    [homeDataSource addMatrixSession:mxSession];
                }
            }
        }
    }
}

- (void)addMatrixSession:(MXSession *)mxSession
{
    // Check whether the controller's view is loaded into memory.
    if (_homeViewController)
    {
        // Check whether the data sources have been initialized.
        if (!homeDataSource)
        {
            // Add first the session. The updated sessions list will be used during data sources initialization.
            mxSessionArray = [NSMutableArray array];
            [mxSessionArray addObject:mxSession];
            
            // Prepare data sources and return
            [self initializeDataSources];
            return;
        }
        else
        {
            // Add the session to the existing home data source
            [homeDataSource addMatrixSession:mxSession];
        }
    }
    
    if (!mxSessionArray)
    {
        mxSessionArray = [NSMutableArray array];
    }
    [mxSessionArray addObject:mxSession];
}

- (void)removeMatrixSession:(MXSession *)mxSession
{
    [homeDataSource removeMatrixSession:mxSession];
    
    // Check whether there are others sessions
    if (!homeDataSource.mxSessions.count)
    {
        [_homeViewController displayList:nil];
        [homeDataSource destroy];
        homeDataSource = nil;
    }
    
    [mxSessionArray removeObject:mxSession];
}

- (void)showAuthenticationScreen
{
    // Check whether an authentication screen is not already shown or preparing
    if (!self.authViewController && !isAuthViewControllerPreparing)
    {
        isAuthViewControllerPreparing = YES;
        
        [[AppDelegate theDelegate] restoreInitialDisplay:^{
            
            [self performSegueWithIdentifier:@"showAuth" sender:self];
            
        }];
    }
}

- (void)showAuthenticationScreenWithRegistrationParameters:(NSDictionary *)parameters
{
    if (self.authViewController)
    {
        NSLog(@"[MasterTabBarController] Universal link: Forward registration parameter to the existing AuthViewController");
        self.authViewController.externalRegistrationParameters = parameters;
    }
    else
    {
        NSLog(@"[MasterTabBarController] Universal link: Logout current sessions and open AuthViewController to complete the registration");
        
        // Keep a ref on the params
        authViewControllerRegistrationParameters = parameters;
        
        // And do a logout out. It will then display AuthViewController
        [[AppDelegate theDelegate] logout];
    }
}

- (void)selectRoomWithId:(NSString*)roomId andEventId:(NSString*)eventId inMatrixSession:(MXSession*)matrixSession
{
    if (_selectedRoomId && [_selectedRoomId isEqualToString:roomId]
        && _selectedEventId && [_selectedEventId isEqualToString:eventId]
        && _selectedRoomSession && _selectedRoomSession == matrixSession)
    {
        // Nothing to do
        return;
    }
    
    _selectedRoomId = roomId;
    _selectedEventId = eventId;
    _selectedRoomSession = matrixSession;
    
    if (roomId && matrixSession)
    {
        [self performSegueWithIdentifier:@"showDetails" sender:self];
    }
    else
    {
        [self closeSelectedRoom];
    }
}

- (void)showRoomPreview:(RoomPreviewData *)roomPreviewData
{
    _selectedRoomPreviewData = roomPreviewData;
    _selectedRoomId = roomPreviewData.roomId;
    _selectedRoomSession = roomPreviewData.mxSession;
    
    [self performSegueWithIdentifier:@"showDetails" sender:self];
}

- (void)closeSelectedRoom
{
    _selectedRoomId = nil;
    _selectedEventId = nil;
    _selectedRoomSession = nil;
    
    if (_currentRoomViewController)
    {
        // If the displayed data is not a preview, let the manager release the room data source
        // (except if the view controller has the room data source ownership).
        if (!_currentRoomViewController.roomPreviewData && _currentRoomViewController.roomDataSource && !_currentRoomViewController.hasRoomDataSourceOwnership)
        {
            MXSession *mxSession = _currentRoomViewController.roomDataSource.mxSession;
            MXKRoomDataSourceManager *roomDataSourceManager = [MXKRoomDataSourceManager sharedManagerForMatrixSession:mxSession];
            
            // Let the manager release live room data sources where the user is in
            [roomDataSourceManager closeRoomDataSource:_currentRoomViewController.roomDataSource forceClose:NO];
        }
        
        [_currentRoomViewController destroy];
        _currentRoomViewController = nil;
    }
}

- (void)dismissUnifiedSearch:(BOOL)animated completion:(void (^)(void))completion
{
    if (unifiedSearchViewController)
    {
        [self.navigationController dismissViewControllerAnimated:animated completion:completion];
    }
    else if (completion)
    {
        completion();
    }
}

#pragma mark -

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([[segue identifier] isEqualToString:@"showDetails"])
    {
        UIViewController *controller;
        if ([[segue destinationViewController] isKindOfClass:[UINavigationController class]])
        {
            controller = [[segue destinationViewController] topViewController];
        }
        else
        {
            controller = [segue destinationViewController];
        }
        
        if ([controller isKindOfClass:[RoomViewController class]])
        {
            // Release existing Room view controller (if any)
            if (_currentRoomViewController)
            {
                // If the displayed data is not a preview, let the manager release the room data source
                // (except if the view controller has the room data source ownership).
                if (!_currentRoomViewController.roomPreviewData && _currentRoomViewController.roomDataSource && !_currentRoomViewController.hasRoomDataSourceOwnership)
                {
                    MXSession *mxSession = _currentRoomViewController.roomDataSource.mxSession;
                    MXKRoomDataSourceManager *roomDataSourceManager = [MXKRoomDataSourceManager sharedManagerForMatrixSession:mxSession];
                    
                    [roomDataSourceManager closeRoomDataSource:_currentRoomViewController.roomDataSource forceClose:NO];
                }
                
                [_currentRoomViewController destroy];
                _currentRoomViewController = nil;
            }
            
            _currentRoomViewController = (RoomViewController *)controller;
            
            if (!_selectedRoomPreviewData)
            {
                MXKRoomDataSource *roomDataSource;
                
//                // Check whether an event has been selected from messages or files search tab. Live timeline or timeline from a search result?
//                MXEvent *selectedSearchEvent = messagesSearchViewController.selectedEvent;
//                MXSession *selectedSearchEventSession = messagesSearchDataSource.mxSession;
//                if (!selectedSearchEvent)
//                {
//                    selectedSearchEvent = filesSearchViewController.selectedEvent;
//                    selectedSearchEventSession = filesSearchDataSource.mxSession;
//                }
                
//                if (!selectedSearchEvent)
                {
                    if (!_selectedEventId)
                    {
                        // LIVE: Show the room live timeline managed by MXKRoomDataSourceManager
                        MXKRoomDataSourceManager *roomDataSourceManager = [MXKRoomDataSourceManager sharedManagerForMatrixSession:_selectedRoomSession];
                        roomDataSource = [roomDataSourceManager roomDataSourceForRoom:_selectedRoomId create:YES];
                    }
                    else
                    {
                        // Open the room on the requested event
                        roomDataSource = [[RoomDataSource alloc] initWithRoomId:_selectedRoomId initialEventId:_selectedEventId andMatrixSession:_selectedRoomSession];
                        [roomDataSource finalizeInitialization];
                        
                        // Give the data source ownership to the room view controller.
                        _currentRoomViewController.hasRoomDataSourceOwnership = YES;
                    }
                }
//                else
//                {
//                    // Search result: Create a temp timeline from the selected event
//                    roomDataSource = [[RoomDataSource alloc] initWithRoomId:selectedSearchEvent.roomId initialEventId:selectedSearchEvent.eventId andMatrixSession:selectedSearchEventSession];
//                    [roomDataSource finalizeInitialization];
//                    
//                    // Give the data source ownership to the room view controller.
//                    _currentRoomViewController.hasRoomDataSourceOwnership = YES;
//                }
                
                [_currentRoomViewController displayRoom:roomDataSource];
            }
            else
            {
                [_currentRoomViewController displayRoomPreview:_selectedRoomPreviewData];
                _selectedRoomPreviewData = nil;
            }
        }
        
        if (self.splitViewController)
        {
            // Refresh selected cell without scrolling the selected cell (We suppose it's visible here)
//            [self refreshCurrentSelectedCellInChild:NO];
            
            // IOS >= 8
            if ([self.splitViewController respondsToSelector:@selector(displayModeButtonItem)])
            {
                controller.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
            }
            
            //
            controller.navigationItem.leftItemsSupplementBackButton = YES;
        }
    }
    else
    {
        // Keep ref on destinationViewController
        [super prepareForSegue:segue sender:sender];
        
        if ([[segue identifier] isEqualToString:@"showAuth"])
        {
            // Keep ref on the authentification view controller while it is displayed
            // ie until we get the notification about a new account
            _authViewController = segue.destinationViewController;
            isAuthViewControllerPreparing = NO;
            
            authViewControllerObserver = [[NSNotificationCenter defaultCenter] addObserverForName:kMXKAccountManagerDidAddAccountNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *notif) {
                
                _authViewController = nil;
                
                [[NSNotificationCenter defaultCenter] removeObserver:authViewControllerObserver];
                authViewControllerObserver = nil;
            }];
            
            // Forward parameters if any
            if (authViewControllerRegistrationParameters)
            {
                _authViewController.externalRegistrationParameters = authViewControllerRegistrationParameters;
                authViewControllerRegistrationParameters = nil;
            }
        }
        else if ([[segue identifier] isEqualToString:@"showUnifiedSearch"])
        {
            unifiedSearchViewController= segue.destinationViewController;
            
            for (MXSession *session in mxSessionArray)
            {
                [unifiedSearchViewController addMatrixSession:session];
            }
        }
    }
}

#pragma mark - 

- (void)promptUserBeforeUsingGoogleAnalytics
{
    NSLog(@"[MasterTabBarController]: Invite the user to send crash reports");
    
    __weak typeof(self) weakSelf = self;
    
    [currentAlert dismiss:NO];
    
    NSString *appDisplayName = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleDisplayName"];
    
    currentAlert = [[MXKAlert alloc] initWithTitle:[NSString stringWithFormat:NSLocalizedStringFromTable(@"google_analytics_use_prompt", @"Vector", nil), appDisplayName]
                                           message:nil
                                             style:MXKAlertStyleAlert];
    
    currentAlert.cancelButtonIndex = [currentAlert addActionWithTitle:[NSBundle mxk_localizedStringForKey:@"no"]
                                                                style:MXKAlertActionStyleDefault
                                                              handler:^(MXKAlert *alert) {
                                                                  
                                                                  [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"enableCrashReport"];
                                                                  [[NSUserDefaults standardUserDefaults] synchronize];
                                                                  
                                                                  if (weakSelf)
                                                                  {
                                                                      __strong __typeof(weakSelf)strongSelf = weakSelf;
                                                                      strongSelf->currentAlert = nil;
                                                                  }
                                                                  
                                                              }];
    [currentAlert addActionWithTitle:[NSBundle mxk_localizedStringForKey:@"yes"]
                               style:MXKAlertActionStyleDefault
                             handler:^(MXKAlert *alert) {
                                 
                                 [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"enableCrashReport"];
                                 [[NSUserDefaults standardUserDefaults] synchronize];
                                 
                                 if (weakSelf)
                                 {
                                     __strong __typeof(weakSelf)strongSelf = weakSelf;
                                     strongSelf->currentAlert = nil;
                                 }
                                 
                                 [[AppDelegate theDelegate] startGoogleAnalytics];
                                 
                             }];
    
    currentAlert.mxkAccessibilityIdentifier = @"HomeVCUseGoogleAnalyticsAlert";
    [currentAlert showInViewController:self];
}

@end
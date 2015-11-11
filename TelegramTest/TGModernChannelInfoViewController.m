//
//  TGModernChannelInfoViewController.m
//  Telegram
//
//  Created by keepcoder on 04/11/15.
//  Copyright © 2015 keepcoder. All rights reserved.
//

#import "TGModernChannelInfoViewController.h"
#import "TGSettingsTableView.h"
#import "TGProfileHeaderRowItem.h"
#import "TGSProfileMediaRowItem.h"
#import "TGProfileParamItem.h"
#import "ComposeActionInfoProfileBehavior.h"
#import "MessagesUtils.h"
#import "TGUserContainerRowItem.h"
#import "TGUserContainerView.h"
#import "TGProfileHeaderRowView.h"
#import "TGModernUserViewController.h"
#import "ComposeActionAddGroupMembersBehavior.h"
#import "TGPhotoViewer.h"
#import "ChatAdminsViewController.h"
#import "ComposeActionBlackListBehavior.h"
#import "ComposeActionChannelMembersBehavior.h"
#import "ComposeChangeChannelDescriptionViewController.h"
#import "ComposeActionChangeChannelAboutBehavior.h"
@interface TGModernChannelInfoViewController ()
@property (nonatomic,strong) TGSettingsTableView *tableView;

@property (nonatomic,strong) TLChat *chat;
@property (nonatomic,strong) TL_conversation *conversation;


@property (nonatomic,strong) TGProfileHeaderRowItem *headerItem;
@property (nonatomic,strong) TGSProfileMediaRowItem *mediaItem;
@property (nonatomic,strong) GeneralSettingsRowItem *notificationItem;
@property (nonatomic,strong) GeneralSettingsBlockHeaderItem *participantsHeaderItem;



@property (nonatomic,strong) ComposeAction *composeActionManagment;
@end

@implementation TGModernChannelInfoViewController


-(void)loadView {
    [super loadView];
    
    _tableView = [[TGSettingsTableView alloc] initWithFrame:self.view.bounds];
    
    [self.view addSubview:_tableView.containerView];
}

-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    self.action.editable = NO;
    
    [self updateActionNavigation];
    
    [self configure];
    
}

-(void)didUpdatedEditableState {
    
    if(!self.action.isEditable && ![self.headerItem.firstChangedValue isEqualToString:_chat.title] && self.headerItem.firstChangedValue.length > 0) {
        
        NSString *prev = _chat.title;
        
        _chat.title = self.headerItem.firstChangedValue;
        
        [Notification perform:CHAT_UPDATE_TITLE data:@{KEY_CHAT:_chat}];
        
        
        [RPCRequest sendRequest:[TLAPI_channels_editTitle createWithChannel:_chat.inputPeer title:self.headerItem.firstChangedValue] successHandler:^(RPCRequest *request, id response) {
            
        } errorHandler:^(RPCRequest *request, RpcError *error) {
            _chat.title = prev;
            
            [Notification perform:CHAT_UPDATE_TITLE data:@{KEY_CHAT:_chat.title}];
        }];
    }
    
    
     [_tableView.list enumerateObjectsUsingBlock:^(TMRowItem *obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        if([obj isKindOfClass:[TMRowItem class]]) {
            [obj setEditable:self.action.isEditable];
        }
        
    }];
    
    [self configure];
    
  
    
    

    
}

-(void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [Notification removeObserver:self];
}

-(void)setChat:(TLChat *)chat {
    
    _chat = chat;
    _conversation = chat.dialog;
    
    _composeActionManagment = [[ComposeAction alloc] initWithBehaviorClass:[ComposeActionBehavior class] filter:@[] object:chat];;
    
    [self setAction:[[ComposeAction alloc] initWithBehaviorClass:[ComposeActionInfoProfileBehavior class] filter:nil object:_conversation]];
    
    _tableView.defaultAnimation = NSTableViewAnimationEffectFade;
    
}



-(void)loadNextParticipants {
    
    [self removeScrollEvent];
    
    int offset = (int)(_tableView.count - 1 - [_tableView indexOfItem:_participantsHeaderItem]);
    
    [RPCRequest sendRequest:[TLAPI_channels_getParticipants createWithChannel:_chat.inputPeer filter:[TL_channelParticipantsRecent create] offset:offset limit:30] successHandler:^(id request, TL_channels_channelParticipants *response) {
        
        
        NSMutableArray *items = [NSMutableArray array];
        
        [response.participants enumerateObjectsUsingBlock:^(TLChatParticipant *obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            TGUserContainerRowItem *user = [[TGUserContainerRowItem alloc] initWithUser:[[UsersManager sharedManager] find:obj.user_id]];
            user.height = 50;
            user.type = SettingsRowItemTypeNone;
            user.editable = self.action.isEditable;
            
            
            [user setStateback:^id(TGGeneralRowItem *item) {
                
                BOOL canRemoveUser = (obj.user_id != [UsersManager currentUserId] && (self.chat.isAdmin || self.chat.isCreator) && ![obj isKindOfClass:[TL_chatParticipantCreator class]]);
                
                return @(canRemoveUser);
                
            }];
            
            __weak TGUserContainerRowItem *weakItem = user;
            
            [user setStateCallback:^{
                
                if(self.action.isEditable) {
                    if([weakItem.stateback(weakItem) boolValue])
                        [self kickParticipant:weakItem];
                } else {
                    TGModernUserViewController *viewController = [[TGModernUserViewController alloc] initWithFrame:NSZeroRect];
                    
                    [viewController setUser:weakItem.user conversation:weakItem.user.dialog];
                    
                    [self.navigationViewController pushViewController:viewController animated:YES];
                }
                
            }];
            
            [items addObject:user];
        }];
        
        
        [_tableView insert:items startIndex:_tableView.list.count tableRedraw:YES];
        
        
        if(items.count > 0)
            [self addScrollEvent];
         else
            [self removeScrollEvent];

        
    } errorHandler:^(id request, RpcError *error) {
        
    }];

}


- (void)scrollViewDocumentOffsetChangingNotificationHandler:(NSNotification *)aNotification {
    
    
    if([self.tableView.scrollView isNeedUpdateTop] ) {
        
        [self loadNextParticipants];
        
    }
    
}

- (void) addScrollEvent {
    id clipView = [[self.tableView enclosingScrollView] contentView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(scrollViewDocumentOffsetChangingNotificationHandler:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:clipView];
}

- (void) removeScrollEvent {
    id clipView = [[self.tableView enclosingScrollView] contentView];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSViewBoundsDidChangeNotification object:clipView];
}


-(void)kickParticipant:(TGUserContainerRowItem *)participant {
    
    
    NSUInteger idx = [_tableView indexOfItem:participant];
    
    _chat.chatFull.participants_count--;
    [_participantsHeaderItem redrawRow];
    
    if(idx != NSNotFound) {
        [_tableView removeItem:participant tableRedraw:YES];
        
        [RPCRequest sendRequest:[TLAPI_channels_kickFromChannel createWithChannel:self.chat.inputPeer user_id:participant.user.inputUser kicked:YES] successHandler:^(id request, id response) {
            
            
        } errorHandler:^(id request, RpcError *error) {
            
            [_tableView insert:participant atIndex:idx tableRedraw:YES];
            
        }];
    }
    
    

}

-(void)configure {
    
    [self.doneButton setHidden:!_chat.isManager || !_chat.isAdmin];
    
    
    [_tableView removeAllItems:YES];
 
    
    
    
    _headerItem = [[TGProfileHeaderRowItem alloc] initWithObject:_conversation];
    
    _headerItem.height = 142;
    
    [_headerItem setEditable:self.action.isEditable];
    
    [_tableView addItem:_headerItem tableRedraw:YES];
    
    
    if(!self.action.isEditable) {
        GeneralSettingsRowItem *adminsItem;
        GeneralSettingsRowItem *membersItem;
        GeneralSettingsRowItem *blacklistItem;
        
        
        if(_chat.username.length > 0) {
            TGProfileParamItem *linkItem = [[TGProfileParamItem alloc] initWithHeight:30];
            
            [linkItem setHeader:NSLocalizedString(@"Profile.ShareLink", nil) withValue:_chat.usernameLink];
            
            [_tableView addItem:linkItem tableRedraw:YES];
            
            [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
        }
        
        
        if(_chat.chatFull.about.length > 0) {
            TGProfileParamItem *aboutItem = [[TGProfileParamItem alloc] initWithHeight:30];
            
            [aboutItem setHeader:NSLocalizedString(@"Profile.About", nil) withValue:_chat.chatFull.about];
            
            [_tableView addItem:aboutItem tableRedraw:YES];
            
            [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
        }
        
        
        if(_chat.isManager || _chat.isAdmin) {
            adminsItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNext callback:^(TGGeneralRowItem *item) {
                
                ComposeManagmentViewController *viewController = [[ComposeManagmentViewController alloc] initWithFrame:NSZeroRect];
                
                [viewController setAction:_composeActionManagment];
                
                [self.navigationViewController pushViewController:viewController animated:YES];
                
            } description:NSLocalizedString(@"Channel.Managment", nil) subdesc:[NSString stringWithFormat:@"%d",_chat.chatFull.admins_count] height:42 stateback:nil];
            
            membersItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNext callback:^(TGGeneralRowItem *item) {
                
                ComposeChannelParticipantsViewController *viewController = [[ComposeChannelParticipantsViewController alloc] initWithFrame:NSZeroRect];
                
                [viewController setAction:[[ComposeAction alloc] initWithBehaviorClass:[ComposeActionChannelMembersBehavior class] filter:@[] object:_chat reservedObjects:@[[TL_channelParticipantsRecent create]]]];
                
                [self.navigationViewController pushViewController:viewController animated:YES];
                
                
            } description:NSLocalizedString(@"Channel.Members", nil) subdesc:[NSString stringWithFormat:@"%d",_chat.chatFull.participants_count] height:42 stateback:nil];
            
            if(_chat.chatFull.kicked_count > 0) {
                blacklistItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNext callback:^(TGGeneralRowItem *item) {
                    
                    ComposeChannelParticipantsViewController *viewController = [[ComposeChannelParticipantsViewController alloc] initWithFrame:NSZeroRect];
                    
                    [viewController setAction:[[ComposeAction alloc] initWithBehaviorClass:[ComposeActionBlackListBehavior class] filter:@[] object:_chat reservedObjects:@[[TL_channelParticipantsKicked create]]]];
                    
                    [self.navigationViewController pushViewController:viewController animated:YES];
                    
                } description:NSLocalizedString(@"Profile.ChannelBlackList", nil) subdesc:[NSString stringWithFormat:@"%d",_chat.chatFull.kicked_count] height:42 stateback:nil];
            }
            
        }
        
        if(adminsItem)
            [_tableView addItem:adminsItem tableRedraw:YES];
        if(membersItem)
            [_tableView addItem:membersItem tableRedraw:YES];
        if(blacklistItem)
            [_tableView addItem:blacklistItem tableRedraw:YES];
        
        if(adminsItem || membersItem || blacklistItem) {
            [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
        }
        
        
        _mediaItem = [[TGSProfileMediaRowItem alloc] initWithObject:_conversation];
        
        weak();
        [_mediaItem setCallback:^(TGGeneralRowItem *item) {
            
            TMCollectionPageController *viewController = [[TMCollectionPageController alloc] initWithFrame:NSZeroRect];
            
            [viewController setConversation:weakSelf.conversation];
            
            [weakSelf.navigationViewController pushViewController:viewController animated:YES];
            
        }];
        
        _mediaItem.height = 50;
        
        [_tableView addItem:_mediaItem tableRedraw:YES];
        
        
        [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
        
        _notificationItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeChoice callback:^(TGGeneralRowItem *item) {
            
        } description:NSLocalizedString(@"Notifications", nil) height:42 stateback:^id(TGGeneralRowItem *item) {
            return [MessagesUtils muteUntil:_conversation.notify_settings.mute_until];
        }];
        
        _notificationItem.menu = [MessagesViewController notifications:^{
            
            [self configure];
            
        } conversation:_conversation click:nil];
        
        
        [_tableView addItem:_notificationItem tableRedraw:YES];
    } else {
        
        GeneralSettingsRowItem *descriptionItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNext callback:^(TGGeneralRowItem *item) {
            
            ComposeChangeChannelDescriptionViewController *viewController = [[ComposeChangeChannelDescriptionViewController alloc] init];
            
            [viewController setAction:[[ComposeAction alloc] initWithBehaviorClass:[ComposeActionChangeChannelAboutBehavior class] filter:nil object:_chat]];
            
            [self.navigationViewController pushViewController:viewController animated:YES];
            
        } description:NSLocalizedString(@"Compose.ChannelAboutPlaceholder", nil) subdesc:_chat.chatFull.about height:42 stateback:nil];
        
        [_tableView addItem:descriptionItem tableRedraw:YES];
        
        
        if(!_chat.isMegagroup) {
            GeneralSettingsRowItem *linkItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNext callback:^(TGGeneralRowItem *item) {
                
                ComposeAction *action = [[ComposeAction alloc] initWithBehaviorClass:[ComposeActionBehavior class]];
                action.result = [[ComposeResult alloc] init];
                action.result.singleObject = _chat;
                ComposeCreateChannelUserNameStepViewController *viewController = [[ComposeCreateChannelUserNameStepViewController alloc] initWithFrame:NSZeroRect];
                
                [viewController setAction:action];
                
                [self.navigationViewController pushViewController:viewController animated:YES];
                
            } description:NSLocalizedString(@"Profile.EditLink", nil) subdesc:_chat.usernameLink height:42 stateback:nil];
            
            [_tableView addItem:linkItem tableRedraw:YES];
            
        }
        
        
        [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
       
        
        if(_chat.isAdmin) {
            GeneralSettingsRowItem *deleteChannelItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNone callback:^(TGGeneralRowItem *item) {
                
                [self.navigationViewController.messagesViewController deleteDialog:_conversation];
                
                
            } description:NSLocalizedString(@"Profile.DeleteChannel", nil) height:42 stateback:nil];
            
            deleteChannelItem.textColor = [NSColor redColor];
            
            [_tableView addItem:deleteChannelItem tableRedraw:YES];
        }
        
    }
    
    if(!_chat.isManager && !_chat.isAdmin && !_chat.isMegagroup) {
        
        [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
        
        GeneralSettingsRowItem *deleteChannelItem = [[GeneralSettingsRowItem alloc] initWithType:SettingsRowItemTypeNone callback:^(TGGeneralRowItem *item) {
            
            [self.navigationViewController.messagesViewController deleteDialog:_conversation];
            
            
        } description:NSLocalizedString(@"Profile.LeaveChannel", nil) height:42 stateback:nil];
        
        deleteChannelItem.textColor = [NSColor redColor];
        
        [_tableView addItem:deleteChannelItem tableRedraw:YES];

    }
    
    if(_chat.isMegagroup) {
        [_tableView addItem:[[TGGeneralRowItem alloc] initWithHeight:20] tableRedraw:YES];
        
        
        _participantsHeaderItem = [[GeneralSettingsBlockHeaderItem alloc] initWithString:[NSString stringWithFormat:NSLocalizedString(@"Modern.Chat.Members", nil),_chat.chatFull.participants_count] height:42 flipped:NO];
        
        [_tableView addItem:_participantsHeaderItem tableRedraw:YES];
        
        [self loadNextParticipants];
    }
    
    
    
}

@end

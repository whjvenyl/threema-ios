//  _____ _
// |_   _| |_  _ _ ___ ___ _ __  __ _
//   | | | ' \| '_/ -_) -_) '  \/ _` |_
//   |_| |_||_|_| \___\___|_|_|_\__,_(_)
//
// Threema iOS Client
// Copyright (c) 2014-2020 Threema GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License, version 3,
// as published by the Free Software Foundation.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

#import "BallotMessageEncoder.h"
#import "BallotChoice.h"
#import "BallotResult.h"
#import "BallotMessage.h"
#import "BallotKeys.h"
#import "Conversation.h"
#import "Contact.h"
#import "MyIdentityStore.h"
#import "JsonUtil.h"

#ifdef DEBUG
  static const DDLogLevel ddLogLevel = DDLogLevelVerbose;
#else
  static const DDLogLevel ddLogLevel = DDLogLevelWarning;
#endif
@implementation BallotMessageEncoder

+ (BoxBallotVoteMessage *)encodeVoteMessageForBallot:(Ballot *)ballot {
    
    NSData *jsonData = [self jsonVoteDataFor:ballot];

    BoxBallotVoteMessage *voteMessage = [[BoxBallotVoteMessage alloc] init];
    voteMessage.messageId = [AbstractMessage randomMessageId];
    voteMessage.date = [NSDate date];
    voteMessage.ballotCreator = ballot.creatorId;
    voteMessage.ballotId = ballot.id;
    voteMessage.jsonChoiceData = jsonData;

    return voteMessage;
}

+ (BoxBallotCreateMessage *)encodeCreateMessageForBallot:(Ballot *)ballot {
    
    NSData *jsonData = [self jsonCreateDataFor:ballot];
    
    BoxBallotCreateMessage *boxMessage = [[BoxBallotCreateMessage alloc] init];
    boxMessage.messageId = [AbstractMessage randomMessageId];
    boxMessage.date = [NSDate date];
    boxMessage.ballotId = ballot.id;
    boxMessage.jsonData = jsonData;
    
    return boxMessage;
}

+ (NSData *)jsonCreateDataFor:(Ballot *)ballot {
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
    
    [dictionary setObject:ballot.title forKey:JSON_KEY_TITLE];
    [dictionary setObject:ballot.type forKey:JSON_KEY_TYPE];
    [dictionary setObject:ballot.state forKey:JSON_KEY_STATE];
    [dictionary setObject:ballot.assessmentType forKey:JSON_KEY_ASSESSMENT_TYPE];
    [dictionary setObject:ballot.choicesType forKey:JSON_KEY_CHOICES_TYPE];

    NSArray *participantArray = nil;
    if ([ballot displayResult]) {
        NSSet *participants = [self participantsForBallot:ballot];
        participantArray = [participants allObjects];
        [dictionary setObject:participantArray forKey:JSON_KEY_PARTICIPANTS];
    }

    NSArray *choices = [self choiceDataForBallot:ballot participants:participantArray];
    [dictionary setObject:choices forKey:JSON_KEY_CHOICES];
    
    NSError *error;
    NSData *jsonData = [JsonUtil serializeJsonFrom:dictionary error:error];
    if (jsonData == nil) {
        DDLogError(@"Error encoding ballot json data %@, %@", error, [error userInfo]);
    }
    
    return jsonData;
}

+ (NSArray *)choiceDataForBallot:(Ballot *)ballot participants:(NSArray *)participants {
    NSMutableArray *choiceData = [NSMutableArray array];
    
    for (BallotChoice *choice in ballot.choices) {
        NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
        
        [dictionary setObject:choice.id forKey:JSON_CHOICE_KEY_ID];
        [dictionary setObject:choice.name forKey:JSON_CHOICE_KEY_NAME];
        [dictionary setObject:choice.orderPosition forKey:JSON_CHOICE_KEY_ORDER_POSITION];
        
        if ([ballot displayResult]) {
            NSArray *result = [self resultForChoice:choice participants:participants];
            [dictionary setObject:result forKey:JSON_CHOICE_KEY_RESULT];
        }
        
        [choiceData addObject: dictionary];
    }
    
    return choiceData;
}

+ (NSArray *)resultForChoice:(BallotChoice *)choice participants:(NSArray *)participants {
    NSMutableArray *resultArray = [NSMutableArray array];

    for (NSString *participantId in participants) {
        BallotResult *result = [choice getResultForId:participantId];
        if (result) {
            [resultArray addObject: result.value];
        } else {
            DDLogError(@"missing ballot result");
            [resultArray addObject: [NSNumber numberWithInt: 0]];
        }
    }
    
    return resultArray;
}

+ (NSData *)jsonVoteDataFor:(Ballot *)ballot {
    NSMutableArray *choiceArray = [NSMutableArray array];
    for (BallotChoice *choice in ballot.choices) {
        
        NSMutableArray *resultArray = [NSMutableArray array];
        
        BallotResult *ownResult = [choice getOwnResult];
        if (ownResult) {
            [resultArray addObject: choice.id];
            [resultArray addObject: ownResult.value];
            
            [choiceArray addObject: resultArray];
        }
    }

    NSError *error;
    NSData *jsonData = [JsonUtil serializeJsonFrom:choiceArray error:error];

    if (jsonData == nil) {
        DDLogError(@"Error encoding ballot vote json data %@, %@", error, [error userInfo]);
    }
    
    return jsonData;
}

+ (NSSet *)participantsForBallot:(Ballot *)ballot {
    NSMutableSet *participants = [NSMutableSet set];
    
    for (BallotChoice *choice in ballot.choices) {
        for (BallotResult *result in choice.result) {
            [participants addObject: result.participantId];
        }
    }

    return participants;
}

#pragma mark - private methods

+ (GroupBallotCreateMessage *)groupBallotCreateMessageFrom:(BoxBallotCreateMessage *)boxBallotMessage forConversation:(Conversation *)conversation {
    GroupBallotCreateMessage *msg = [[GroupBallotCreateMessage alloc] init];
    msg.messageId = boxBallotMessage.messageId;
    msg.date = boxBallotMessage.date;
    msg.groupId = conversation.groupId;
    msg.jsonData = boxBallotMessage.jsonData;
    msg.ballotId = boxBallotMessage.ballotId;
    
    if (conversation.contact == nil) {
        msg.groupCreator = [MyIdentityStore sharedMyIdentityStore].identity;
    } else {
        msg.groupCreator = conversation.contact.identity;
    }
    
    return msg;
}

+ (GroupBallotVoteMessage *)groupBallotVoteMessageFrom:(BoxBallotVoteMessage *)boxBallotMessage forConversation:(Conversation *)conversation {
    GroupBallotVoteMessage *msg = [[GroupBallotVoteMessage alloc] init];
    msg.messageId = boxBallotMessage.messageId;
    msg.date = boxBallotMessage.date;
    msg.groupId = conversation.groupId;
    msg.ballotCreator = boxBallotMessage.ballotCreator;
    msg.ballotId = boxBallotMessage.ballotId;
    msg.jsonChoiceData = boxBallotMessage.jsonChoiceData;
    
    if (conversation.contact == nil) {
        msg.groupCreator = [MyIdentityStore sharedMyIdentityStore].identity;
    } else {
        msg.groupCreator = conversation.contact.identity;
    }
    
    return msg;
}

@end

/* Copyright 2013 Google Inc. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "JavascriptEventLoader.h"
#import "PacoExperiment.h"
#import "PacoClient.h"
#import "PacoEventManager.h"
#import "PacoEvent.h"
#import "NSDate+Paco.h"
#import "PacoExperimentInput.h"
#import "PacoExperimentFeedback.h"

@interface JavascriptEventLoader()

@property(nonatomic, strong) NSArray* events;
@end

@implementation JavascriptEventLoader

- (id)initWithExperiment:(PacoExperiment*)experiment {
  self = [super init];
  if (self) {
    _experiment = experiment;
  }
  return self;
}

+ (instancetype)loaderForExperiment:(PacoExperiment*)experiment {
  return [[[self class] alloc] initWithExperiment:experiment];
}

+ (NSString*)convertEventsToJsonString:(NSArray*)events experiment:(PacoExperiment*)experiment{
  NSMutableArray* eventJsonList = [NSMutableArray arrayWithCapacity:[events count]];
  for (PacoEvent* event in events) {
    NSArray* responseListWithImageString = [event responseListWithImageString];
    NSMutableArray* newResponses = [NSMutableArray array];
    for (NSDictionary* responseDict in responseListWithImageString) {
      PacoExperimentInput* input = [experiment inputWithId:responseDict[@"inputId"]];
      if (!input) { //join, stop event
        continue;
      }
      NSMutableDictionary* newDict = [NSMutableDictionary dictionary];
      newDict[@"inputId"] = input.inputIdentifier;
      // deprecate inputName in favor of name. Some experiments still use it though
      newDict[@"inputName"] = input.name;
      newDict[@"name"] = input.name;
      newDict[@"responseType"] = input.responseType;
      newDict[@"isMultiselect"] = @(input.multiSelect);
      if (input.text) {
        newDict[@"prompt"] = input.text;
      }
      id answer = responseDict[@"answer"];
      NSAssert([answer isKindOfClass:[NSString class]] || [answer isKindOfClass:[NSNumber class]],
               @"answer must be either a number or a string");
      newDict[@"answer"] = answer; //TODO: may need to change this for list type answer
      // deprecate answerOrder for answerRaw
      newDict[@"answerOrder"] = answer;
      newDict[@"answerRaw"] = answer;
      [newResponses addObject:newDict];
    }
    if (0 == [newResponses count]) {
      continue;
    }
    
    NSMutableDictionary* eventJson = [NSMutableDictionary dictionary];
    eventJson[@"responses"] = newResponses;
    eventJson[@"isMissedSignal"] = @(event.responseTime == nil);
    if (event.responseTime) {
      eventJson[@"responseTime"] = @([event.responseTime pacoGetMilliSeconds]);
    }
    eventJson[@"isSelfReport"] = @(event.scheduledTime == nil);
    if (event.scheduledTime) {
      eventJson[@"scheduleTime"] = @([event.scheduledTime pacoGetMilliSeconds]);
    }
    [eventJsonList addObject:eventJson];
  }
  
  NSError* error = nil;
  NSData* jsonData = [NSJSONSerialization dataWithJSONObject:eventJsonList
                                                     options:NSJSONWritingPrettyPrinted
                                                       error:&error];
  NSString* jsonString = nil;
  if (!error) {
    jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
  } else {
    DDLogError(@"Failed to converting eventJsonList to NSData: %@", [error description]);
  }
  return jsonString;
}


- (void)loadEventsIfNeeded {
  @synchronized(self) {
    if (!self.events) {
      NSArray* events =
          [[PacoClient sharedInstance].eventManager eventsForExperiment:self.experiment.instanceId];
      self.events = (events != nil) ? events : [NSArray array];
    }
  }
}

- (NSString*)getAllEvents {
  return [self loadAllEvents];
}

- (NSString*)loadAllEvents {
  @synchronized(self) {
    [self loadEventsIfNeeded];
    return [JavascriptEventLoader convertEventsToJsonString:self.events experiment:self.experiment];
  }
}

- (NSString*)jsonStringForLastEvent {
  @synchronized(self) {
    [self loadEventsIfNeeded];
    if (0 == [self.events count]) {
      return @"[]";
    }
    NSArray* arrayWithLastEvent = [NSArray arrayWithObject:[self.events lastObject]];
    return [JavascriptEventLoader convertEventsToJsonString:arrayWithLastEvent
                                                 experiment:self.experiment];
  }
}


- (NSString*)feedbackString {
  return [self.experiment feedback].text;
}


@end

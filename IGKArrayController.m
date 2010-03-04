//
//  IGKArrayController.m
//  Ingredients
//
//  Created by Alex Gordon on 13/02/2010.
//  Copyright 2010 Fileability. All rights reserved.
//

#import "IGKArrayController.h"
#import "Ingredients_AppDelegate.h"
#import "IGKDocRecordManagedObject.h"

@implementation IGKArrayController

@synthesize predicate;
@synthesize smartSortDescriptors;
@synthesize currentSortDescriptors;
@synthesize maxRows;
@synthesize vipObject;

- (void)awakeFromNib
{
	[tableView setDataSource:self];
}

- (void)fetch
{	
	//TODO: Eventually we want to fetch on another thread. There are still some synchronization issues to sort out
	//dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
	
	if (!predicate)
		return;
	
	if (!currentSortDescriptors)
		currentSortDescriptors = smartSortDescriptors;
	
	NSManagedObjectContext *ctx = [[[NSApp delegate] kitController] managedObjectContext];
	
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	[request setEntity:[NSEntityDescription entityForName:@"DocRecord" inManagedObjectContext:ctx]];
	[request setPredicate:predicate];
	
	
	[request setFetchLimit:500];
	if (maxRows != 0 && maxRows < 500)
	{
		//Limit the list to 100 items. This could be changed to more, if requested, but my view is that if anybody needs more than 100, our sorting isn't smart enough
		[request setFetchLimit:maxRows];
	}
				
	//Sort results by priority, so that when we LIMIT our list, only the low priority items are cut
	[request setSortDescriptors:[NSArray arrayWithObject:[NSSortDescriptor sortDescriptorWithKey:@"priority" ascending:NO]]];

	//Fetch a list of objects
	fetchedObjects = [ctx executeFetchRequest:request error:nil];
	
	//NSFetchRequests and NSComparator-based sort descriptors apparently don't go together, so we can't tell the fetch request to sort using this descriptor
	//Besides, it's far better to be sorting 100 objects with our expensive comparator than 10000
	fetchedObjects = [fetchedObjects sortedArrayUsingDescriptors:currentSortDescriptors];
	
	if ([fetchedObjects containsObject:vipObject])
		fetchContainsVipObject = YES;
	else
		fetchContainsVipObject = NO;
	
	//});
}
- (void)refresh
{
	[self refreshAndSelectFirst:YES renderSelection:NO];
}
- (void)refreshAndSelectFirst:(BOOL)selectFirst renderSelection:(BOOL)renderSelection
{
	//Fetch a new list of objects and refresh the table
	[self fetch];
	
	[tableView reloadData];
	
	if (selectFirst)
	{
		//Select the first row, scroll to it, and notify the delegate
		[tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];;
		[tableView scrollRowToVisible:0];
		
		if (renderSelection)
			[[tableView delegate] tableViewSelectionDidChange:nil];
	}
}

- (IBAction)selectPrevious:(id)sender
{
	NSInteger row = [tableView selectedRow] - 1;
	
	if (row < 0 || row >= [fetchedObjects count])
		return;
	
	[tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[tableView scrollRowToVisible:row];
	
	[[tableView delegate] tableViewSelectionDidChange:nil];
}
- (IBAction)selectNext:(id)sender
{
	NSInteger row = [tableView selectedRow] + 1;
	
	if (row < 0 || row >= [self numberOfRowsInTableView:tableView])
		return;
	
	[tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
	[tableView scrollRowToVisible:row];
	
	[[tableView delegate] tableViewSelectionDidChange:nil];
}

- (id)objectAtRow:(NSInteger)row
{
	if (row < 0 || row >= [self numberOfRowsInTableView:tableView])
		return nil;
	
	if (vipObject && !fetchContainsVipObject)
	{
		if (row == 0)
			return vipObject;
		
		return [fetchedObjects objectAtIndex:row - 1];
	}
	else
		return [fetchedObjects objectAtIndex:row];
}

- (id)selection
{
	NSInteger row = [tableView selectedRow];
	
	if (row < 0 || row >= [self numberOfRowsInTableView:tableView])
		return nil;
	
	if (vipObject && !fetchContainsVipObject)
	{
		if (row == 0)
			return vipObject;
		
		return [fetchedObjects objectAtIndex:row - 1];
	}
	else
		return [fetchedObjects objectAtIndex:row];
}

- (void)tableView:(NSTableView *)tv sortDescriptorsDidChange:(NSArray *)oldDescriptors
{
	currentSortDescriptors = [tableView sortDescriptors];
	if (![currentSortDescriptors count])
	{
		currentSortDescriptors = smartSortDescriptors;
	}
	else
	{
		id firstObject = [currentSortDescriptors objectAtIndex:0];
		id newSortDescriptor = firstObject;
		
		if ([[firstObject key] isEqual:@"xentity"])
		{
			newSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:nil ascending:[firstObject ascending] comparator:^ NSComparisonResult (id obja, id objb) {
				
				//So neither a nor b starts with q. Now we apply prioritization. Some types get priority over others. For instance, a class > method > typedef > constant
				NSUInteger objaPriority = [[obja valueForKey:@"priority"] shortValue];
				NSUInteger objbPriority = [[objb valueForKey:@"priority"] shortValue];
				
				//Higher priorities are better
				if (objaPriority > objbPriority)
					return NSOrderedAscending;
				else if (objaPriority < objbPriority)
					return NSOrderedDescending;
				
				//If the have the same priority, just compare the names of their entities (this is arbitrary, we just want to make sure there isn't an enum between two structs)
				return [[[obja entity] name] localizedCompare:[[objb entity] name]];
			}];
		}
		else if ([[firstObject key] isEqual:@"xcontainername"])
		{
			BOOL isAsc = [firstObject ascending];
			newSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:nil ascending:YES comparator:^ NSComparisonResult (id obja, id objb) {
				id a = [obja xcontainername];
				id b = [objb xcontainername];
				
				BOOL hasA = ([a length] != 0);
				BOOL hasB = ([b length] != 0);
				
				if (hasA == hasB)
				{
					NSComparisonResult r = [a localizedCompare:b];
					if (isAsc)
						return r;
					
					//If this is a descending sort, then invert the result of the comparison
					//We do this instead of using the ascending: option because items with an empty container name should always appear at the bottom, regardless of sort direction 
					if (r == NSOrderedAscending)
						return NSOrderedDescending;
					
					if (r == NSOrderedDescending)
						return NSOrderedAscending;
					
					return NSOrderedSame;
				}
				else if (hasA && !hasB)
				{
					return NSOrderedAscending;
				}
				
				return NSOrderedDescending;
			}];
		}
		
		currentSortDescriptors = [NSArray arrayWithObject:newSortDescriptor];
	}
	
	[self refresh];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tv
{
	return [fetchedObjects count] + (vipObject && !fetchContainsVipObject ? 1 : 0);
}
- (id)tableView:(NSTableView *)tv objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= [fetchedObjects count])
		return nil;
	
	//Get the object at this row
	id fo /* sure */ = nil;
	if (row == 0 && vipObject)
		fo = vipObject;
	else if (vipObject)
		fo = [fetchedObjects objectAtIndex:row - 1];
	else
		fo = [fetchedObjects objectAtIndex:row];
	
	id identifier = [tableColumn identifier];
	
	//*** Icons ***
	if ([identifier isEqual:@"normalIcon"])
	{
		if (row == [tableView selectedRow])
			return [fo valueForKey:@"selectedIcon"];
		else
			return [fo valueForKey:@"normalIcon"];
	}
	
	//*** Titles ***
	if ([identifier isEqual:@"name"])
	{
		return [fo valueForKey:@"name"];
	}
	
	//*** Container Names ***
	if ([identifier isEqual:@"xcontainername"])
	{
		return [fo valueForKey:@"xcontainername"];
	}
	
	return nil;
}

@end

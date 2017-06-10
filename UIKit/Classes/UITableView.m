/*
 * Copyright (c) 2011, The Iconfactory. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Neither the name of The Iconfactory nor the names of its contributors may
 *    be used to endorse or promote products derived from this software without
 *    specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE ICONFACTORY BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
 * OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 * ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "UITableView.h"
#import "UITableViewCell+UIPrivate.h"
#import "UIColor.h"
#import "UITouch.h"
#import "UITableViewSection.h"
#import "UITableViewSectionLabel.h"
#import "UIScreenAppKitIntegration.h"
#import "UIWindow.h"
#import "UIKitView.h"
#import "UIApplicationAppKitIntegration.h"
#import <AppKit/NSMenu.h>
#import <AppKit/NSMenuItem.h>
#import <AppKit/NSEvent.h>

// http://stackoverflow.com/questions/235120/whats-the-uitableview-index-magnifying-glass-character
NSString *const UITableViewIndexSearch = @"{search}";

const CGFloat _UITableViewDefaultRowHeight = 43;

@implementation UITableView {
    BOOL _needsReload;
    NSIndexPath *_selectedRow;
    NSIndexPath *_highlightedRow;
    NSMutableDictionary *_cachedCells;
    NSMutableSet *_reusableCells;
    NSMutableArray *_sections;
    
    struct {
        unsigned heightForRowAtIndexPath : 1;
        unsigned heightForHeaderInSection : 1;
        unsigned heightForFooterInSection : 1;
        unsigned viewForHeaderInSection : 1;
        unsigned viewForFooterInSection : 1;
        unsigned willSelectRowAtIndexPath : 1;
        unsigned didSelectRowAtIndexPath : 1;
        unsigned willDeselectRowAtIndexPath : 1;
        unsigned didDeselectRowAtIndexPath : 1;
        unsigned willBeginEditingRowAtIndexPath : 1;
        unsigned didEndEditingRowAtIndexPath : 1;
        unsigned titleForDeleteConfirmationButtonForRowAtIndexPath: 1;
    } _delegateHas;
    
    struct {
        unsigned numberOfSectionsInTableView : 1;
        unsigned titleForHeaderInSection : 1;
        unsigned titleForFooterInSection : 1;
        unsigned commitEditingStyle : 1;
        unsigned canEditRowAtIndexPath : 1;
    } _dataSourceHas;
}

- (id)initWithFrame:(CGRect)frame
{
    return [self initWithFrame:frame style:UITableViewStylePlain];
}

- (id)initWithFrame:(CGRect)frame style:(UITableViewStyle)theStyle
{
    if ((self=[super initWithFrame:frame])) {
        _style = theStyle;
        // cell缓存字典
        _cachedCells = [[NSMutableDictionary alloc] init];
        // Section 缓存数组
        _sections = [[NSMutableArray alloc] init];
        // 复用的cell 集合
        _reusableCells = [[NSMutableSet alloc] init];

        self.separatorColor = [UIColor colorWithRed:.88f green:.88f blue:.88f alpha:1];
        self.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        self.showsHorizontalScrollIndicator = NO;
        self.allowsSelection = YES;
        self.allowsSelectionDuringEditing = NO;
        self.sectionHeaderHeight = self.sectionFooterHeight = 22;
        self.alwaysBounceVertical = YES;
        
        if (_style == UITableViewStylePlain) {
            self.backgroundColor = [UIColor whiteColor];
        }
        
        // 加入 layout 标记，进行手动触发布局设置
        [self _setNeedsReload];
    }
    return self;
}


- (void)setDataSource:(id<UITableViewDataSource>)newSource
{
    _dataSource = newSource;

    _dataSourceHas.numberOfSectionsInTableView = [_dataSource respondsToSelector:@selector(numberOfSectionsInTableView:)];
    _dataSourceHas.titleForHeaderInSection = [_dataSource respondsToSelector:@selector(tableView:titleForHeaderInSection:)];
    _dataSourceHas.titleForFooterInSection = [_dataSource respondsToSelector:@selector(tableView:titleForFooterInSection:)];
    _dataSourceHas.commitEditingStyle = [_dataSource respondsToSelector:@selector(tableView:commitEditingStyle:forRowAtIndexPath:)];
    _dataSourceHas.canEditRowAtIndexPath = [_dataSource respondsToSelector:@selector(tableView:canEditRowAtIndexPath:)];
    
    [self _setNeedsReload];
}

- (void)setDelegate:(id<UITableViewDelegate>)newDelegate
{
    [super setDelegate:newDelegate];

    _delegateHas.heightForRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:heightForRowAtIndexPath:)];
    _delegateHas.heightForHeaderInSection = [newDelegate respondsToSelector:@selector(tableView:heightForHeaderInSection:)];
    _delegateHas.heightForFooterInSection = [newDelegate respondsToSelector:@selector(tableView:heightForFooterInSection:)];
    _delegateHas.viewForHeaderInSection = [newDelegate respondsToSelector:@selector(tableView:viewForHeaderInSection:)];
    _delegateHas.viewForFooterInSection = [newDelegate respondsToSelector:@selector(tableView:viewForFooterInSection:)];
    _delegateHas.willSelectRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)];
    _delegateHas.didSelectRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)];
    _delegateHas.willDeselectRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:willDeselectRowAtIndexPath:)];
    _delegateHas.didDeselectRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:didDeselectRowAtIndexPath:)];
    _delegateHas.willBeginEditingRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:willBeginEditingRowAtIndexPath:)];
    _delegateHas.didEndEditingRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:didEndEditingRowAtIndexPath:)];
    _delegateHas.titleForDeleteConfirmationButtonForRowAtIndexPath = [newDelegate respondsToSelector:@selector(tableView:titleForDeleteConfirmationButtonForRowAtIndexPath:)];
}

- (void)setRowHeight:(CGFloat)newHeight
{
    _rowHeight = newHeight;
    [self setNeedsLayout];
}

- (void)_updateSectionsCache
{
    // uses the dataSource to rebuild the cache.
    // 使用 dataSource 来创建缓存容器
    // if there's no dataSource, this can't do anything else.
    // 如果没有 dataSource 则放弃重用操作
    // note that I'm presently caching and hanging on to views and titles for section headers which is something
    // the real UIKit appears to fetch more on-demand than this. so far this has not been a problem.

    // remove all previous section header/footer views
    for (UITableViewSection *previousSectionRecord in _sections) {
        [previousSectionRecord.headerView removeFromSuperview];
        [previousSectionRecord.footerView removeFromSuperview];
    }
    
    // clear the previous cache
    [_sections removeAllObjects];
    
    if (_dataSource) {
        // compute the heights/offsets of everything
        // 根据 dataSource 计算高度和偏移量
        const CGFloat defaultRowHeight = _rowHeight ?: _UITableViewDefaultRowHeight;
        // 获取 Section 的数目
        const NSInteger numberOfSections = [self numberOfSections];
        for (NSInteger section=0; section<numberOfSections; section++) {
            // 获取当前 section 的 cell 个数
            const NSInteger numberOfRowsInSection = [self numberOfRowsInSection:section];
            // 当前 section 的记录
            UITableViewSection *sectionRecord = [[UITableViewSection alloc] init];
            sectionRecord.headerTitle = _dataSourceHas.titleForHeaderInSection? [self.dataSource tableView:self titleForHeaderInSection:section] : nil;
            sectionRecord.footerTitle = _dataSourceHas.titleForFooterInSection? [self.dataSource tableView:self titleForFooterInSection:section] : nil;
            
            sectionRecord.headerHeight = _delegateHas.heightForHeaderInSection? [self.delegate tableView:self heightForHeaderInSection:section] : _sectionHeaderHeight;
            sectionRecord.footerHeight = _delegateHas.heightForFooterInSection ? [self.delegate tableView:self heightForFooterInSection:section] : _sectionFooterHeight;

            sectionRecord.headerView = (sectionRecord.headerHeight > 0 && _delegateHas.viewForHeaderInSection)? [self.delegate tableView:self viewForHeaderInSection:section] : nil;
            sectionRecord.footerView = (sectionRecord.footerHeight > 0 && _delegateHas.viewForFooterInSection)? [self.delegate tableView:self viewForFooterInSection:section] : nil;

            // make a default section header view if there's a title for it and no overriding view
            if (!sectionRecord.headerView && sectionRecord.headerHeight > 0 && sectionRecord.headerTitle) {
                sectionRecord.headerView = [UITableViewSectionLabel sectionLabelWithTitle:sectionRecord.headerTitle];
            }
            
            // make a default section footer view if there's a title for it and no overriding view
            if (!sectionRecord.footerView && sectionRecord.footerHeight > 0 && sectionRecord.footerTitle) {
                sectionRecord.footerView = [UITableViewSectionLabel sectionLabelWithTitle:sectionRecord.footerTitle];
            }

            if (sectionRecord.headerView) {
                [self addSubview:sectionRecord.headerView];
            } else {
                sectionRecord.headerHeight = 0;
            }
            
            if (sectionRecord.footerView) {
                [self addSubview:sectionRecord.footerView];
            } else {
                sectionRecord.footerHeight = 0;
            }

            // 存储 cell 的高度数组
            CGFloat *rowHeights = malloc(numberOfRowsInSection * sizeof(CGFloat));
            // 当前 section 的总高度
            CGFloat totalRowsHeight = 0;
            
            for (NSInteger row=0; row<numberOfRowsInSection; row++) {
                const CGFloat rowHeight = _delegateHas.heightForRowAtIndexPath? [self.delegate tableView:self heightForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]] : defaultRowHeight;
                rowHeights[row] = rowHeight;
                totalRowsHeight += rowHeight;
            }
            
            sectionRecord.rowsHeight = totalRowsHeight;
            [sectionRecord setNumberOfRows:numberOfRowsInSection withHeights:rowHeights];
            free(rowHeights);
            
            [_sections addObject:sectionRecord];
        }
    }
}

- (void)_updateSectionsCacheIfNeeded
{
    // if there's a cache already in place, this doesn't do anything,
    // otherwise calls _updateSectionsCache.
    // this is called from _setContentSize and other places that require access
    // to the section caches (mostly for size-related information)
    
    if ([_sections count] == 0) {
        [self _updateSectionsCache];
    }
}

- (void)_setContentSize
{
    // first calls _updateSectionsCacheIfNeeded, then sets the scroll view's size
    // taking into account the size of the header, footer, and all rows.
    // should be called by reloadData, setFrame, header/footer setters.
    
    [self _updateSectionsCacheIfNeeded];
    
    CGFloat height = _tableHeaderView? _tableHeaderView.frame.size.height : 0;
    
    for (UITableViewSection *section in _sections) {
        height += [section sectionHeight];
    }
    
    if (_tableFooterView) {
        height += _tableFooterView.frame.size.height;
    }
    
    self.contentSize = CGSizeMake(0,height);	
}

- (void)_layoutTableView
{
    // lays out headers and rows that are visible at the time. this should also do cell
    // dequeuing and keep a list of all existing cells that are visible and those
    // that exist but are not visible and are reusable
    // if there's no section cache, no rows will be laid out but the header/footer will (if any).
    // 在需要渲染时放置需要的 Header 和 Cell
    // 缓存所有出现的单元格， 并添加至复用容器
    // 之后那些不在显示但是已经出现的 Cell 将会被复用
    
    // 获取容器视图相对父类视图的尺寸及坐标
    const CGSize boundsSize = self.bounds.size;
    // 获取向下滑动偏移量
    const CGFloat contentOffset = self.contentOffset.y;
    // 获取可视矩形框的尺寸
    const CGRect visibleBounds = CGRectMake(0,contentOffset,boundsSize.width,boundsSize.height);
    // 表高纪录值
    CGFloat tableHeight = 0;
    // 如果有 header 则需要额外计算
    if (_tableHeaderView) {
        CGRect tableHeaderFrame = _tableHeaderView.frame;
        tableHeaderFrame.origin = CGPointZero;
        tableHeaderFrame.size.width = boundsSize.width;
        _tableHeaderView.frame = tableHeaderFrame;
        tableHeight += tableHeaderFrame.size.height;
    }
    
    // layout sections and rows
    // availableCell 记录当前正在显示的 Cell
    NSMutableDictionary *availableCells = [_cachedCells mutableCopy];
    const NSInteger numberOfSections = [_sections count];
    [_cachedCells removeAllObjects];
    
    // 滑动列表，更新当前显示容器
    for (NSInteger section=0; section<numberOfSections; section++) {
        // 当前 section 的可视区域
        CGRect sectionRect = [self rectForSection:section];
        
        tableHeight += sectionRect.size.height;
        
        // 如果当前 section 和 可视区域有重叠
        if (CGRectIntersectsRect(sectionRect, visibleBounds)) {
            const CGRect headerRect = [self rectForHeaderInSection:section];
            const CGRect footerRect = [self rectForFooterInSection:section];
            // 获取 section 数据
            UITableViewSection *sectionRecord = [_sections objectAtIndex:section];
            // cell 的个数
            const NSInteger numberOfRows = sectionRecord.numberOfRows;

            if (sectionRecord.headerView) {
                // section 的 headerView 的 frame
                sectionRecord.headerView.frame = headerRect;
            }
            
            if (sectionRecord.footerView) {
                // section 的 footerView 的 frame
                sectionRecord.footerView.frame = footerRect;
            }
            
            for (NSInteger row=0; row<numberOfRows; row++) {
                // 获取 indexPath
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:section];
                // 拿到 indexPath 的 rect
                CGRect rowRect = [self rectForRowAtIndexPath:indexPath];
                if (CGRectIntersectsRect(rowRect,visibleBounds) && rowRect.size.height > 0) {
                    // 如果 indexPath 和 visibleBounds 有交际，并且 height > 0
                    // 说明要显示该 indexPath 位置的 cell
                    // 获取 cell
                    UITableViewCell *cell = [availableCells objectForKey:indexPath] ?: [self.dataSource tableView:self cellForRowAtIndexPath:indexPath];
                    if (cell) {
                        // 将 cell 加入到缓存中
                        [_cachedCells setObject:cell forKey:indexPath];
                        // 将 cell 从 availableCells 中删除
                        [availableCells removeObjectForKey:indexPath];
                        cell.highlighted = [_highlightedRow isEqual:indexPath];
                        cell.selected = [_selectedRow isEqual:indexPath];
                        // 修改 cell 的 frame
                        cell.frame = rowRect;
                        cell.backgroundColor = self.backgroundColor;
                        [cell _setSeparatorStyle:_separatorStyle color:_separatorColor];
                        [self addSubview:cell];
                    }
                }
            }
        }
    }
    
    // remove old cells, but save off any that might be reusable
    for (UITableViewCell *cell in [availableCells allValues]) {
        if (cell.reuseIdentifier) {
            // 将剩余的可复用的 cell 加入到 _reusableCells 数组中
            [_reusableCells addObject:cell];
        } else {
            // 不可复用的销毁
            [cell removeFromSuperview];
        }
    }
    
    // non-reusable cells should end up dealloced after at this point, but reusable ones live on in _reusableCells.
    
    // now make sure that all available (but unused) reusable cells aren't on screen in the visible area.
    // this is done becaue when resizing a table view by shrinking it's height in an animation, it looks better. The reason is that
    // when an animation happens, it sets the frame to the new (shorter) size and thus recalcuates which cells should be visible.
    // If it removed all non-visible cells, then the cells on the bottom of the table view would disappear immediately but before
    // the frame of the table view has actually animated down to the new, shorter size. So the animation is jumpy/ugly because
    // the cells suddenly disappear instead of seemingly animating down and out of view like they should. This tries to leave them
    // on screen as long as possible, but only if they don't get in the way.
    
    // 确保所有的可用 (未出现在屏幕上) 的复用 cell 在 availableCells 中
    NSArray* allCachedCells = [_cachedCells allValues];
    for (UITableViewCell *cell in _reusableCells) {
        if (CGRectIntersectsRect(cell.frame,visibleBounds) && ![allCachedCells containsObject: cell]) {
            [cell removeFromSuperview];
        }
    }
    
    if (_tableFooterView) {
        CGRect tableFooterFrame = _tableFooterView.frame;
        tableFooterFrame.origin = CGPointMake(0,tableHeight);
        tableFooterFrame.size.width = boundsSize.width;
        _tableFooterView.frame = tableFooterFrame;
    }
}

- (CGRect)_CGRectFromVerticalOffset:(CGFloat)offset height:(CGFloat)height
{
    return CGRectMake(0,offset,self.bounds.size.width,height);
}

- (CGFloat)_offsetForSection:(NSInteger)index
{
    CGFloat offset = _tableHeaderView? _tableHeaderView.frame.size.height : 0;
    
    for (NSInteger s=0; s<index; s++) {
        offset += [[_sections objectAtIndex:s] sectionHeight];
    }
    
    return offset;
}

- (CGRect)rectForSection:(NSInteger)section
{
    [self _updateSectionsCacheIfNeeded];
    return [self _CGRectFromVerticalOffset:[self _offsetForSection:section] height:[[_sections objectAtIndex:section] sectionHeight]];
}

- (CGRect)rectForHeaderInSection:(NSInteger)section
{
    [self _updateSectionsCacheIfNeeded];
    return [self _CGRectFromVerticalOffset:[self _offsetForSection:section] height:[[_sections objectAtIndex:section] headerHeight]];
}

- (CGRect)rectForFooterInSection:(NSInteger)section
{
    [self _updateSectionsCacheIfNeeded];
    UITableViewSection *sectionRecord = [_sections objectAtIndex:section];
    CGFloat offset = [self _offsetForSection:section];
    offset += sectionRecord.headerHeight;
    offset += sectionRecord.rowsHeight;
    return [self _CGRectFromVerticalOffset:offset height:sectionRecord.footerHeight];
}

- (CGRect)rectForRowAtIndexPath:(NSIndexPath *)indexPath
{
    [self _updateSectionsCacheIfNeeded];

    if (indexPath && indexPath.section < [_sections count]) {
        UITableViewSection *sectionRecord = [_sections objectAtIndex:indexPath.section];
        const NSUInteger row = indexPath.row;
        
        if (row < sectionRecord.numberOfRows) {
            // 拿到该 section 中所有的 cell 的高度数组
            CGFloat *rowHeights = sectionRecord.rowHeights;
            // 获取到该 section 的偏移量
            CGFloat offset = [self _offsetForSection:indexPath.section];
            
            offset += sectionRecord.headerHeight;
            
            for (NSInteger currentRow=0; currentRow<row; currentRow++) {
                // 计算 indexPath 在 tableView 上的便宜量
                offset += rowHeights[currentRow];
            }
            // 获取 indexPath 的 rect
            return [self _CGRectFromVerticalOffset:offset height:rowHeights[row]];
        }
    }
    
    return CGRectZero;
}

- (void) beginUpdates
{
}

- (void)endUpdates
{
}

- (UITableViewCell *)cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // this is allowed to return nil if the cell isn't visible and is not restricted to only returning visible cells
    // so this simple call should be good enough.
    return [_cachedCells objectForKey:indexPath];
}

- (NSArray *)indexPathsForRowsInRect:(CGRect)rect
{
    // This needs to return the index paths even if the cells don't exist in any caches or are not on screen
    // For now I'm assuming the cells stretch all the way across the view. It's not clear to me if the real
    // implementation gets anal about this or not (haven't tested it).

    [self _updateSectionsCacheIfNeeded];

    NSMutableArray *results = [[NSMutableArray alloc] init];
    const NSInteger numberOfSections = [_sections count];
    CGFloat offset = _tableHeaderView? _tableHeaderView.frame.size.height : 0;
    
    for (NSInteger section=0; section<numberOfSections; section++) {
        UITableViewSection *sectionRecord = [_sections objectAtIndex:section];
        CGFloat *rowHeights = sectionRecord.rowHeights;
        const NSInteger numberOfRows = sectionRecord.numberOfRows;
        
        offset += sectionRecord.headerHeight;

        if (offset + sectionRecord.rowsHeight >= rect.origin.y) {
            for (NSInteger row=0; row<numberOfRows; row++) {
                const CGFloat height = rowHeights[row];
                CGRect simpleRowRect = CGRectMake(rect.origin.x, offset, rect.size.width, height);
                
                if (CGRectIntersectsRect(rect,simpleRowRect)) {
                    [results addObject:[NSIndexPath indexPathForRow:row inSection:section]];
                } else if (simpleRowRect.origin.y > rect.origin.y+rect.size.height) {
                    break;	// don't need to find anything else.. we are past the end
                }
                
                offset += height;
            }
        } else {
            offset += sectionRecord.rowsHeight;
        }
        
        offset += sectionRecord.footerHeight;
    }
    
    return results;
}

- (NSIndexPath *)indexPathForRowAtPoint:(CGPoint)point
{
    NSArray *paths = [self indexPathsForRowsInRect:CGRectMake(point.x,point.y,1,1)];
    return ([paths count] > 0)? [paths objectAtIndex:0] : nil;
}

- (NSArray *)indexPathsForVisibleRows
{
    [self _layoutTableView];

    NSMutableArray *indexes = [NSMutableArray arrayWithCapacity:[_cachedCells count]];
    const CGRect bounds = self.bounds;

    // Special note - it's unclear if UIKit returns these in sorted order. Because we're assuming that visibleCells returns them in order (top-bottom)
    // and visibleCells uses this method, I'm going to make the executive decision here and assume that UIKit probably does return them sorted - since
    // there's nothing warning that they aren't. :)
    
    for (NSIndexPath *indexPath in [[_cachedCells allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if (CGRectIntersectsRect(bounds,[self rectForRowAtIndexPath:indexPath])) {
            [indexes addObject:indexPath];
        }
    }

    return indexes;
}

- (NSArray *)visibleCells
{
    NSMutableArray *cells = [[NSMutableArray alloc] init];
    for (NSIndexPath *index in [self indexPathsForVisibleRows]) {
        UITableViewCell *cell = [self cellForRowAtIndexPath:index];
        if (cell) {
            [cells addObject:cell];
        }
    }
    return cells;
}

- (void)setTableHeaderView:(UIView *)newHeader
{
    if (newHeader != _tableHeaderView) {
        [_tableHeaderView removeFromSuperview];
        _tableHeaderView = newHeader;
        [self _setContentSize];
        [self addSubview:_tableHeaderView];
    }
}

- (void)setTableFooterView:(UIView *)newFooter
{
    if (newFooter != _tableFooterView) {
        [_tableFooterView removeFromSuperview];
        _tableFooterView = newFooter;
        [self _setContentSize];
        [self addSubview:_tableFooterView];
    }
}

- (void)setBackgroundView:(UIView *)backgroundView
{
    if (_backgroundView != backgroundView) {
        [_backgroundView removeFromSuperview];
        _backgroundView = backgroundView;
        [self insertSubview:_backgroundView atIndex:0];
    }
}

- (NSInteger)numberOfSections
{
    if (_dataSourceHas.numberOfSectionsInTableView) {
        return [self.dataSource numberOfSectionsInTableView:self];
    } else {
        return 1;
    }
}

- (NSInteger)numberOfRowsInSection:(NSInteger)section
{
    return [self.dataSource tableView:self numberOfRowsInSection:section];
}

- (void)reloadData
{
    // clear the caches and remove the cells since everything is going to change
    // 清楚之前的缓存并删除 Cell
    [[_cachedCells allValues] makeObjectsPerformSelector:@selector(removeFromSuperview)];
    // 复用 Cell 也进行删除
    [_reusableCells makeObjectsPerformSelector:@selector(removeFromSuperview)];
    [_reusableCells removeAllObjects];
    [_cachedCells removeAllObjects];

    // clear prior selection
    // 清楚选择的 cell
    _selectedRow = nil;
    // 删除高亮的 cell
    _highlightedRow = nil;
    
    // trigger the section cache to be repopulated
    // 更新所有 sections 的状态
    [self _updateSectionsCache];
    // 设置 size
    [self _setContentSize];
    
    _needsReload = NO;
}

- (void)reloadRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation
{
    [self reloadData];
}

- (void)_reloadDataIfNeeded
{
    if (_needsReload) {
        [self reloadData];
    }
}

- (void)_setNeedsReload
{
    _needsReload = YES;
    [self setNeedsLayout];
}

- (void)layoutSubviews
{
    _backgroundView.frame = self.bounds;
    // 根据标记确定是否执行数据更新
    [self _reloadDataIfNeeded];
    // 布局入口
    [self _layoutTableView];
    [super layoutSubviews];
}

- (void)setFrame:(CGRect)frame
{
    const CGRect oldFrame = self.frame;
    if (!CGRectEqualToRect(oldFrame,frame)) {
        [super setFrame:frame];

        if (oldFrame.size.width != frame.size.width) {
            [self _updateSectionsCache];
        }

        [self _setContentSize];
    }
}

- (NSIndexPath *)indexPathForSelectedRow
{
    return _selectedRow;
}

- (NSIndexPath *)indexPathForCell:(UITableViewCell *)cell
{
    for (NSIndexPath *index in [_cachedCells allKeys]) {
        if ([_cachedCells objectForKey:index] == cell) {
            return index;
        }
    }
    
    return nil;
}

- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated
{
    if (indexPath && [indexPath isEqual:_selectedRow]) {
        [self cellForRowAtIndexPath:_selectedRow].selected = NO;
        _selectedRow = nil;
    }
}

- (void)selectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated scrollPosition:(UITableViewScrollPosition)scrollPosition
{
    // unlike the other methods that I've tested, the real UIKit appears to call reload during selection if the table hasn't been reloaded
    // yet. other methods all appear to rebuild the section cache "on-demand" but don't do a "proper" reload. for the sake of attempting
    // to maintain a similar delegate and dataSource access pattern to the real thing, I'll do it this way here. :)
    [self _reloadDataIfNeeded];
    
    if (![_selectedRow isEqual:indexPath]) {
        [self deselectRowAtIndexPath:_selectedRow animated:animated];
        _selectedRow = indexPath;
        [self cellForRowAtIndexPath:_selectedRow].selected = YES;
    }
    
    // I did not verify if the real UIKit will still scroll the selection into view even if the selection itself doesn't change.
    // this behavior was useful for Ostrich and seems harmless enough, so leaving it like this for now.
    [self scrollToRowAtIndexPath:_selectedRow atScrollPosition:scrollPosition animated:animated];
}

- (void)_setUserSelectedRowAtIndexPath:(NSIndexPath *)rowToSelect
{
    if (_delegateHas.willSelectRowAtIndexPath) {
        rowToSelect = [self.delegate tableView:self willSelectRowAtIndexPath:rowToSelect];
    }
    
    NSIndexPath *selectedRow = [self indexPathForSelectedRow];
    
    if (selectedRow && ![selectedRow isEqual:rowToSelect]) {
        NSIndexPath *rowToDeselect = selectedRow;
        
        if (_delegateHas.willDeselectRowAtIndexPath) {
            rowToDeselect = [self.delegate tableView:self willDeselectRowAtIndexPath:rowToDeselect];
        }
        
        [self deselectRowAtIndexPath:rowToDeselect animated:NO];
        
        if (_delegateHas.didDeselectRowAtIndexPath) {
            [self.delegate tableView:self didDeselectRowAtIndexPath:rowToDeselect];
        }
    }
    
    [self selectRowAtIndexPath:rowToSelect animated:NO scrollPosition:UITableViewScrollPositionNone];
    
    if (_delegateHas.didSelectRowAtIndexPath) {
        [self.delegate tableView:self didSelectRowAtIndexPath:rowToSelect];
    }
}

- (void)_scrollRectToVisible:(CGRect)aRect atScrollPosition:(UITableViewScrollPosition)scrollPosition animated:(BOOL)animated
{
    if (!CGRectIsNull(aRect) && aRect.size.height > 0) {
        // adjust the rect based on the desired scroll position setting
        switch (scrollPosition) {
            case UITableViewScrollPositionNone:
                break;
                
            case UITableViewScrollPositionTop:
                aRect.size.height = self.bounds.size.height;
                break;

            case UITableViewScrollPositionMiddle:
                aRect.origin.y -= (self.bounds.size.height / 2.f) - aRect.size.height;
                aRect.size.height = self.bounds.size.height;
                break;

            case UITableViewScrollPositionBottom:
                aRect.origin.y -= self.bounds.size.height - aRect.size.height;
                aRect.size.height = self.bounds.size.height;
                break;
        }
        
        [self scrollRectToVisible:aRect animated:animated];
    }
}

- (void)scrollToNearestSelectedRowAtScrollPosition:(UITableViewScrollPosition)scrollPosition animated:(BOOL)animated
{
    [self _scrollRectToVisible:[self rectForRowAtIndexPath:[self indexPathForSelectedRow]] atScrollPosition:scrollPosition animated:animated];
}

- (void)scrollToRowAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(UITableViewScrollPosition)scrollPosition animated:(BOOL)animated
{
    [self _scrollRectToVisible:[self rectForRowAtIndexPath:indexPath] atScrollPosition:scrollPosition animated:animated];
}

- (UITableViewCell *)dequeueReusableCellWithIdentifier:(NSString *)identifier
{
    for (UITableViewCell *cell in _reusableCells) {
        if ([cell.reuseIdentifier isEqualToString:identifier]) {
            UITableViewCell *strongCell = cell;
            
            // the above strongCell reference seems totally unnecessary, but without it ARC apparently
            // ends up releasing the cell when it's removed on this line even though we're referencing it
            // later in this method by way of the cell variable. I do not like this.
            [_reusableCells removeObject:cell];

            [strongCell prepareForReuse];
            return strongCell;
        }
    }
    
    return nil;
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animate
{
    _editing = editing;
}

- (void)setEditing:(BOOL)editing
{
    [self setEditing:editing animated:NO];
}

- (void)insertSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation
{
    [self reloadData];
}

- (void)deleteSections:(NSIndexSet *)sections withRowAnimation:(UITableViewRowAnimation)animation
{
    [self reloadData];
}

- (void)insertRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation
{
    [self reloadData];
}

- (void)deleteRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(UITableViewRowAnimation)animation
{
    [self reloadData];
}

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event
{
}

- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event
{
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (!_highlightedRow) {
        UITouch *touch = [touches anyObject];
        const CGPoint location = [touch locationInView:self];
        
        _highlightedRow = [self indexPathForRowAtPoint:location];
        [self cellForRowAtIndexPath:_highlightedRow].highlighted = YES;
    }

    if (_highlightedRow) {
        [self cellForRowAtIndexPath:_highlightedRow].highlighted = NO;
        [self _setUserSelectedRowAtIndexPath:_highlightedRow];
        _highlightedRow = nil;
    }
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event
{
    if (_highlightedRow) {
        [self cellForRowAtIndexPath:_highlightedRow].highlighted = NO;
        _highlightedRow = nil;
    }
}

- (BOOL)_canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    // it's YES by default until the dataSource overrules
    return _dataSourceHas.commitEditingStyle && (!_dataSourceHas.canEditRowAtIndexPath || [_dataSource tableView:self canEditRowAtIndexPath:indexPath]);
}

- (void)_beginEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([self _canEditRowAtIndexPath:indexPath]) {
        self.editing = YES;
        
        if (_delegateHas.willBeginEditingRowAtIndexPath) {
            [self.delegate tableView:self willBeginEditingRowAtIndexPath:indexPath];
        }
        
        // deferring this because it presents a modal menu and that's what we do everywhere else in Chameleon
        [self performSelector:@selector(_showEditMenuForRowAtIndexPath:) withObject:indexPath afterDelay:0];
    }
}

- (void)_endEditingRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.editing) {
        self.editing = NO;

        if (_delegateHas.didEndEditingRowAtIndexPath) {
            [self.delegate tableView:self didEndEditingRowAtIndexPath:indexPath];
        }
    }
}

- (void)_showEditMenuForRowAtIndexPath:(NSIndexPath *)indexPath
{
    // re-checking for safety since _showEditMenuForRowAtIndexPath is deferred. this may be overly paranoid.
    if ([self _canEditRowAtIndexPath:indexPath]) {
        UITableViewCell *cell = [self cellForRowAtIndexPath:indexPath];
        NSString *menuItemTitle = nil;
        
        // fetch the title for the delete menu item
        if (_delegateHas.titleForDeleteConfirmationButtonForRowAtIndexPath) {
            menuItemTitle = [self.delegate tableView:self titleForDeleteConfirmationButtonForRowAtIndexPath:indexPath];
        }
        if ([menuItemTitle length] == 0) {
            menuItemTitle = @"Delete";
        }

        cell.highlighted = YES;
        
        NSMenuItem *theItem = [[NSMenuItem alloc] initWithTitle:menuItemTitle action:NULL keyEquivalent:@""];

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
        [menu setAutoenablesItems:NO];
        [menu setAllowsContextMenuPlugIns:NO];
        [menu addItem:theItem];
        
        // calculate the mouse's current position so we can present the menu from there since that's normal OSX behavior
        NSPoint mouseLocation = [NSEvent mouseLocation];
        CGPoint screenPoint = [self.window.screen convertPoint:NSPointToCGPoint(mouseLocation) fromScreen:nil];

        // modally present a menu with the single delete option on it, if it was selected, then do the delete, otherwise do nothing
        const BOOL didSelectItem = [menu popUpMenuPositioningItem:nil atLocation:NSPointFromCGPoint(screenPoint) inView:self.window.screen.UIKitView];
        
        UIApplicationInterruptTouchesInView(nil);

        if (didSelectItem) {
            [_dataSource tableView:self commitEditingStyle:UITableViewCellEditingStyleDelete forRowAtIndexPath:indexPath];
        }

        cell.highlighted = NO;
    }

    // all done
    [self _endEditingRowAtIndexPath:indexPath];
}

- (void)rightClick:(UITouch *)touch withEvent:(UIEvent *)event
{
    CGPoint location = [touch locationInView:self];
    NSIndexPath *touchedRow = [self indexPathForRowAtPoint:location];
    
    // this is meant to emulate UIKit's swipe-to-delete feature on Mac by way of a right-click menu
    if (touchedRow && [self _canEditRowAtIndexPath:touchedRow]) {
        [self _beginEditingRowAtIndexPath:touchedRow];
    }
}

// these can come down to use from AppKit if the table view somehow ends up in the responder chain.
// arrow keys move the selection, page up/down keys scroll the view

- (void)moveUp:(id)sender
{
    NSIndexPath *selection = self.indexPathForSelectedRow;
    
    if (selection.row > 0) {
        selection = [NSIndexPath indexPathForRow:selection.row-1 inSection:selection.section];
    } else if (selection.row == 0 && selection.section > 0) {
        for (NSInteger section = selection.section - 1; section >= 0; section--) {
            const NSInteger rows = [self numberOfRowsInSection:section];
            
            if (rows > 0) {
                selection = [NSIndexPath indexPathForRow:rows-1 inSection:section];
                break;
            }
        }
    }
    
    if (![selection isEqual:self.indexPathForSelectedRow]) {
        [self _setUserSelectedRowAtIndexPath:selection];
        [NSCursor setHiddenUntilMouseMoves:YES];
    }
}

- (void)moveDown:(id)sender
{
    NSIndexPath *selection = self.indexPathForSelectedRow;
    
    if ((selection.row + 1) < [self numberOfRowsInSection:selection.section]) {
        selection = [NSIndexPath indexPathForRow:selection.row+1 inSection:selection.section];
    } else {
        for (NSInteger section = selection.section + 1; section < self.numberOfSections; section++) {
            const NSInteger rows = [self numberOfRowsInSection:section];
            
            if (rows > 0) {
                selection = [NSIndexPath indexPathForRow:0 inSection:section];
                break;
            }
        }
    }
    
    if (![selection isEqual:self.indexPathForSelectedRow]) {
        [self _setUserSelectedRowAtIndexPath:selection];
        [NSCursor setHiddenUntilMouseMoves:YES];
    }
}

- (void)pageUp:(id)sender
{
    NSArray *visibleRows = [self indexPathsForVisibleRows];

    if ([visibleRows count] > 0) {
        [self scrollToRowAtIndexPath:[visibleRows objectAtIndex:0] atScrollPosition:UITableViewScrollPositionBottom animated:YES];
        [NSCursor setHiddenUntilMouseMoves:YES];
        [self flashScrollIndicators];
    }
}

- (void)pageDown:(id)sender
{
	[self scrollToRowAtIndexPath:[[self indexPathsForVisibleRows] lastObject] atScrollPosition:UITableViewScrollPositionTop animated:YES];
    [NSCursor setHiddenUntilMouseMoves:YES];
	[self flashScrollIndicators];
}

@end

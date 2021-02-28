import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart';

import 'calendar.dart';
import 'calendardaymarker.dart';
import 'calendarevent.dart';
import 'sliverlistcalendar.dart';

class SliverScrollViewCalendarElement extends StatelessElement
    implements CalendarEventElement {
  SliverScrollViewCalendarElement(SliverScrollViewCalendar widget, this._state)
      : super(widget);

  TZDateTime _startWindow;
  TZDateTime _endWindow;
  CalendarViewType _type;
  Set<int> _rangeVisible = new Set<int>();
  // View index is the number of days since the epoch.
  int _startDisplayIndex;
  int _beginningRangeIndex;
  int _endingRangeIndex;
  Location _currentLocation;
  int _nowIndex;
  CalendarWidgetState _state;
  StreamSubscription<int> _topIndexChangedSubscription;

  void initState() {
    _state.element = this;

    SliverScrollViewCalendar calendarWidget =
        widget as SliverScrollViewCalendar;
    if (calendarWidget.location == null) {
      _currentLocation = local;
    } else {
      _currentLocation = calendarWidget.location;
    }
    _nowIndex = CalendarEvent.indexFromMilliseconds(
        new TZDateTime.now(_currentLocation), _currentLocation);
    _startDisplayIndex = calendarWidget.initialDate.millisecondsSinceEpoch ~/
            Duration.millisecondsPerDay *
            2 -
        2;
    _beginningRangeIndex = calendarWidget.beginningRangeDate != null
        ? calendarWidget.beginningRangeDate.millisecondsSinceEpoch ~/
                Duration.millisecondsPerDay *
                2 -
            2
        : -1;
    _endingRangeIndex = calendarWidget.endingRangeDate != null
        ? calendarWidget.endingRangeDate.millisecondsSinceEpoch ~/
                Duration.millisecondsPerDay *
                2 -
            2
        : -1;
    _state.currentTopDisplayIndex = _startDisplayIndex ~/ 2;
    debugPrint("Display index $_startDisplayIndex $_nowIndex");
    _type = calendarWidget.view;
    // Normalize the dates.
    TZDateTime normalizedStart = new TZDateTime(
        _currentLocation,
        calendarWidget.initialDate.year,
        calendarWidget.initialDate.month,
        calendarWidget.initialDate.day);
    switch (_type) {
      case CalendarViewType.Schedule:
        // Grab 60 days ahead and 60 days behind.
        _startWindow = normalizedStart.subtract(new Duration(days: 60));
        _endWindow = normalizedStart.add(new Duration(days: 60));
        break;
      case CalendarViewType.Week:
        _startWindow = new TZDateTime(
            _currentLocation,
            calendarWidget.initialDate.year,
            calendarWidget.initialDate.month,
            calendarWidget.initialDate.day);
        if (_startWindow.weekday != 0) {
          if (_startWindow.weekday < 0) {
            _startWindow = _startWindow.subtract(new Duration(
                days: 0 - DateTime.daysPerWeek + _startWindow.weekday));
          } else {
            _startWindow = _startWindow
                .subtract(new Duration(days: 0 - _startWindow.weekday));
          }
          _endWindow =
              _startWindow.add(new Duration(days: DateTime.daysPerWeek));
        }
        break;
      case CalendarViewType.Month:
        _startWindow = new TZDateTime(_currentLocation,
            calendarWidget.initialDate.year, calendarWidget.initialDate.month);
        _endWindow = new TZDateTime(
            _currentLocation,
            calendarWidget.initialDate.year,
            calendarWidget.initialDate.month + 1);
        break;
    }
    updateEvents();
    _topIndexChangedSubscription =
        _state.indexChangeStream.listen((int newIndex) {
      // NB: this is the display index, so in GM
      int ms = newIndex * Duration.millisecondsPerDay;

      bool changed = false;
      TZDateTime top =
          new TZDateTime.fromMillisecondsSinceEpoch(_currentLocation, ms);
      if (_startWindow.difference(top).inDays < 30 ||
          top.isBefore(_startWindow)) {
        // Set a new start window.
        debugPrint("Moving start window $newIndex $top $_startWindow");
        _startWindow = top.subtract(new Duration(days: 60));
        changed = true;
      }
      if (_endWindow.difference(top).inDays < 30 || top.isAfter(_endWindow)) {
        _endWindow = top.add(new Duration(days: 60));
        changed = true;
      }
      if (changed) {
        debugPrint("Updating between $_startWindow $_endWindow");
        updateEvents();
      }
    });
  }

  @override
  void updateEvents() {
    // Now do stuff with our events.
    _state.updateInternalEvents(_startWindow, _endWindow);
    markNeedsBuild();
  }

  @override
  void scrollToDate(DateTime time) {
    SliverScrollViewCalendar calendarWidget =
        widget as SliverScrollViewCalendar;
    RenderBox firstChild = _state.renderSliverList.firstChild;
    int scrollToIndex =
        time.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay * 2;
    if (firstChild != null) {
      final SliverMultiBoxAdaptorParentData firstParentData =
          firstChild.parentData as SliverMultiBoxAdaptorParentData;
      // Already there...
      if (firstParentData.index == scrollToIndex ||
          firstParentData.index == scrollToIndex + 1) {
        return;
      }
      debugPrint(
          'Looking for $scrollToIndex ${firstParentData.index} ${time.month} ${time.day}');
      if (firstParentData.index < scrollToIndex) {
        // See if it is in the visible set.
        RenderBox lastChild = _state.renderSliverList.lastChild;
        if (lastChild != null) {
          final SliverMultiBoxAdaptorParentData lastParentData =
              lastChild.parentData as SliverMultiBoxAdaptorParentData;

          if (lastParentData.index > scrollToIndex) {
            // In range, easier scroll.
            SliverMultiBoxAdaptorParentData parentData;
            RenderBox currentChild = firstChild;
            do {
              currentChild = _state.renderSliverList.childAfter(currentChild);
              if (currentChild == null) {
                debugPrint('No current child! $currentChild');
                break;
              }
              parentData =
                  currentChild.parentData as SliverMultiBoxAdaptorParentData;
              debugPrint('finding index ${parentData.index} $currentChild');
            } while (parentData.index != scrollToIndex);
            if (parentData != null && parentData.index == scrollToIndex) {
              // Yay!  Scroll there and end.
              calendarWidget.controller.animateTo(parentData.layoutOffset,
                  curve: Curves.easeIn,
                  duration: new Duration(milliseconds: 250));
              return;
            }
          }
        }
      }
      _state.renderSliverList.newTopScrollIndex = scrollToIndex + 2;
      // Move the index up and down by a lot to force the refresh/move.
      if (firstParentData.index < scrollToIndex) {
        calendarWidget.controller.jumpTo(calendarWidget.controller.offset +
            Duration.microsecondsPerDay.toDouble());
      } else {
        calendarWidget.controller.jumpTo(calendarWidget.controller.offset -
            Duration.microsecondsPerDay.toDouble());
      }
    }
  }

  @override
  void mount(Element parent, dynamic newSlot) {
    initState();
    super.mount(parent, newSlot);
  }

  @override
  void rebuild() {
    _rangeVisible.clear();
    super.rebuild();
  }

  Widget _buildCalendarWidget(BuildContext context, int mainIndex) {
    final DateFormat monthFormat =
        new DateFormat.MMM(Localizations.localeOf(context).languageCode);
    final DateFormat dayOfWeekFormat =
        new DateFormat.E(Localizations.localeOf(context).languageCode);
    final DateFormat dayOfMonthFormat =
        new DateFormat.MMMd(Localizations.localeOf(context).languageCode);

    SliverScrollViewCalendar calendarWidget =
        widget as SliverScrollViewCalendar;
    const double widthFirst = 40.0;
    const double inset = 5.0;
    int ms = mainIndex ~/ 2 * Duration.millisecondsPerDay;
    DateTime time = new DateTime.fromMillisecondsSinceEpoch(ms);
    if (mainIndex % 2 == 1) {
      int index = CalendarEvent.indexFromMilliseconds(time, null);
      if (_state.events.containsKey(index)) {
        List<CalendarEvent> events = _state.events[index];
        DateTime day = events[0].instant;
        final Size screenSize = MediaQuery.of(context).size;
        double widthSecond = screenSize.width - widthFirst - inset;
        TextStyle style = Theme.of(context).textTheme.subhead.copyWith(
              fontWeight: FontWeight.w300,
            );
        List<Widget> displayEvents = <Widget>[];
        if (index == _nowIndex) {
          TZDateTime nowTime = new TZDateTime.now(_currentLocation);
          style.copyWith(color: Theme.of(context).accentColor);
          int lastMS =
              nowTime.millisecondsSinceEpoch - Duration.millisecondsPerDay;
          bool shownDivider = false;
          for (CalendarEvent e in events) {
            if (e.instant.millisecondsSinceEpoch > lastMS &&
                nowTime.isBefore(e.instantEnd)) {
              // Stick in the 'now marker' right here.
              displayEvents.add(new CalendarDayMarker(
                color: Colors.redAccent,
              ));
              displayEvents.add(_state.widget.buildItem(context, e));
              shownDivider = true;
            } else if (e.instant.isAfter(nowTime) &&
                e.instantEnd.isBefore(nowTime)) {
              // Show on top of this card.
              displayEvents.add(new Stack(
                children: <Widget>[
                  _state.widget.buildItem(context, e),
                  new CalendarDayMarker(color: Colors.redAccent),
                ],
              ));
            } else {
              displayEvents.add(_state.widget.buildItem(context, e));
            }
          }
          if (!shownDivider) {
            displayEvents.add(new CalendarDayMarker(color: Colors.redAccent));
          }
        } else {
          displayEvents = events
              .map<Widget>(
                (CalendarEvent e) => _state.widget.buildItem(context, e),
              )
              .toList();
        }

        return new Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            new Container(
              constraints: new BoxConstraints.tightFor(width: widthFirst),
              margin: new EdgeInsets.only(top: 14.0, left: inset),
              child: new Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  new Text(
                    dayOfWeekFormat.format(day),
                    style: style,
                  ),
                  new Text(
                    dayOfMonthFormat.format(day),
                    style: style.copyWith(fontSize: 12.0),
                  ),
                ],
              ),
            ),
            new Container(
              constraints: new BoxConstraints.tightFor(width: widthSecond),
              margin: new EdgeInsets.only(top: 10.0),
              child: new Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisAlignment: MainAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: displayEvents,
              ),
            ),
          ],
        );
      } else {
        int startIndex = index;
        DateTime start = time;
        // Show day/month headers
        if (!_state.events.containsKey(CalendarEvent.indexFromMilliseconds(
                time.add(oneDay), _currentLocation)) ||
            !_state.events.containsKey(CalendarEvent.indexFromMilliseconds(
                time.subtract(oneDay), _currentLocation))) {
          DateTime hardStart = new DateTime(start.year, start.month, 1);
          DateTime hardEnd =
              new DateTime(start.year, start.month + 1).subtract(oneDay);
          DateTime cur = start;
          DateTime last = cur;
          bool foundEnd = false;
          if (_rangeVisible.contains(startIndex)) {
            foundEnd = true;
          }
          int lastIndex = startIndex;
          while (hardEnd.compareTo(last) > 0 &&
              !_state.events.containsKey(lastIndex + 1)) {
            last = last.add(oneDay);
            lastIndex =
                CalendarEvent.indexFromMilliseconds(last, _currentLocation);
            if (_rangeVisible.contains(lastIndex)) {
              foundEnd = true;
            }
          }
          // Pull back to the start too.
          cur = start;
          while (hardStart.compareTo(cur) < 0 &&
              !_state.events.containsKey(startIndex)) {
            start = cur;
            cur = cur.subtract(oneDay);
            if (hardStart.compareTo(cur) < 0) {
              startIndex =
                  CalendarEvent.indexFromMilliseconds(cur, _currentLocation);
              if (_rangeVisible.contains(startIndex)) {
                foundEnd = true;
              }
            }
          }
          if (index % 50 == 0) {
            debugPrint('loc $index $startIndex $lastIndex $foundEnd');
          }

          if (!foundEnd &&
              !_rangeVisible.contains(startIndex) &&
              !_rangeVisible.contains(lastIndex)) {
            _rangeVisible.add(startIndex);
            _rangeVisible.add(lastIndex);
            // Range
            if (_nowIndex > startIndex && _nowIndex <= lastIndex) {
              debugPrint('$startIndex $lastIndex $_nowIndex $start $last');
              return new Container(
                margin: new EdgeInsets.only(top: 15.0, left: 5.0),
                child: new Stack(
                  children: <Widget>[
                    new Text(
                      monthFormat.format(start) +
                          " " +
                          start.day.toString() +
                          " - " +
                          last.day.toString(),
                      style: Theme.of(context).textTheme.subhead.copyWith(
                            fontSize: 12.0,
                            fontWeight: FontWeight.w300,
                          ),
                    ),
                    new CalendarDayMarker(
                      indent: widthFirst,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
              );
            } else {
              return new Container(
                margin: new EdgeInsets.only(top: 15.0, left: 5.0),
                child: new Text(
                  monthFormat.format(start) +
                      " " +
                      start.day.toString() +
                      " - " +
                      last.day.toString(),
                  style: Theme.of(context).textTheme.subhead.copyWith(
                        fontSize: 12.0,
                        fontWeight: FontWeight.w300,
                      ),
                ),
              );
            }
          }
        } else {
          // Single day
          if (_nowIndex == index) {
            return new Container(
              margin: new EdgeInsets.only(top: 10.0, left: 5.0),
              child: new Stack(
                children: <Widget>[
                  new Text(
                    MaterialLocalizations.of(context).formatMediumDate(start),
                    style: Theme.of(context).textTheme.subhead.copyWith(
                          fontSize: 12.0,
                          fontWeight: FontWeight.w300,
                        ),
                  ),
                  new CalendarDayMarker(
                    indent: widthFirst,
                    color: Colors.redAccent,
                  ),
                ],
              ),
            );
          } else {
            return new Container(
              margin: new EdgeInsets.only(top: 10.0, left: 5.0),
              child: new Text(
                MaterialLocalizations.of(context).formatMediumDate(start),
                style: Theme.of(context).textTheme.subhead.copyWith(
                      fontSize: 12.0,
                      fontWeight: FontWeight.w300,
                    ),
              ),
            );
          }
        }
      }
    } else {
      // Put in the month header if we are at the start of the month.
      TZDateTime start =
          new TZDateTime(_currentLocation, time.year, time.month, time.day);
      if (start.day == 1) {
        return new Container(
          decoration: calendarWidget.monthHeader != null
              ? new BoxDecoration(
                  color: Colors.blue,
                  image: new DecorationImage(
                    image: calendarWidget.monthHeader,
                    fit: BoxFit.cover,
                  ),
                )
              : null,
          margin: new EdgeInsets.only(top: 30.0),
          padding: new EdgeInsets.only(left: 5.0),
          constraints: calendarWidget.monthHeader != null
              ? new BoxConstraints(minHeight: 100.0, maxHeight: 100.0)
              : null,
          child: new Text(
            MaterialLocalizations.of(context).formatMonthYear(start),
            style: Theme.of(context).textTheme.title.copyWith(
                  color: calendarWidget.monthHeader != null
                      ? Colors.white
                      : Colors.black,
                  fontSize: 30.0,
                ),
          ),
        );
      }
    }
    return const SizedBox(height: 0.1);
  }

  SliverListCenter _buildCalendarList() {
    SliverScrollViewCalendar calendarWidget =
        widget as SliverScrollViewCalendar;
    return new SliverListCenter(
      startIndex: _startDisplayIndex,
      state: _state,
      controller: calendarWidget.controller,
      delegate: new SliverChildBuilderDelegate(
        (BuildContext context, int index) {
          if (index < _beginningRangeIndex ||
              (_endingRangeIndex != -1 && index > _endingRangeIndex)) {
            return null;
          }
          return _buildCalendarWidget(context, index);
        },
      ),
    );
  }

  void didUpdateWidget(covariant SliverScrollViewCalendar oldWidget) {}

  @override
  void update(StatelessWidget newWidget) {
    super.update(newWidget);
    assert(widget == newWidget);
    // Notice that we mark ourselves as dirty before calling didUpdateWidget to
    // let authors call setState from within didUpdateWidget without triggering
    // asserts.
    markNeedsBuild();
    rebuild();
  }

  @override
  void activate() {
    super.activate();
    markNeedsBuild();
  }

  @override
  void unmount() {
    super.unmount();
    //_state.dispose();
    _topIndexChangedSubscription?.cancel();
    _topIndexChangedSubscription = null;
  }
}

class SliverScrollViewCalendar extends ScrollView {
  SliverScrollViewCalendar({
    @required this.initialDate,
    @required double initialScrollOffset,
    @required this.state,
    this.beginningRangeDate,
    this.endingRangeDate,
    this.monthHeader,
    this.view = CalendarViewType.Schedule,
    this.location,
  }) : super(
            scrollDirection: Axis.vertical,
            shrinkWrap: true,
            controller: new ScrollController(
                initialScrollOffset: initialScrollOffset)) {
    state.controller = controller;
  }

  final DateTime initialDate;
  final DateTime beginningRangeDate;
  final DateTime endingRangeDate;
  final CalendarViewType view;
  final Location location;
  final ImageProvider monthHeader;
  final CalendarWidgetState state;

  @override
  SliverScrollViewCalendarElement createElement() =>
      new SliverScrollViewCalendarElement(this, state);

  @override
  List<Widget> buildSlivers(BuildContext context) {
    SliverScrollViewCalendarElement element =
        context as SliverScrollViewCalendarElement;
    return <Widget>[
      element._buildCalendarList(),
    ];
  }
}

///
/// This wraps the calendar im a scroll view.
///
class WrappedScrollViewCalendar extends StatefulWidget {
  WrappedScrollViewCalendar({
    @required this.initialDate,
    @required this.initialScrollOffset,
    @required this.state,
    this.beginningRangeDate,
    this.endingRangeDate,
    this.monthHeader,
    this.tapToCloseHeader = true,
    this.view = CalendarViewType.Schedule,
    this.location,
  });

  final DateTime initialDate;
  final DateTime beginningRangeDate;
  final DateTime endingRangeDate;
  final CalendarViewType view;
  final Location location;
  final double initialScrollOffset;
  final ImageProvider monthHeader;
  final bool tapToCloseHeader;
  final CalendarWidgetState state;

  @override
  _WrapperScrollViewCalendarState createState() {
    return _WrapperScrollViewCalendarState();
  }
}

class _WrapperScrollViewCalendarState extends State<WrappedScrollViewCalendar> {
  StreamSubscription<bool> _onHeaderExpandChange;

  @override
  void initState() {
    super.initState();
    _onHeaderExpandChange =
        widget.state.headerExpandedChangeStream.listen((bool update) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
    _onHeaderExpandChange?.cancel();
    _onHeaderExpandChange = null;
  }

  void _handleTapOnHeaderExpanded() {
    widget.state.headerExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.tapToCloseHeader && widget.state.headerExpanded
          ? _handleTapOnHeaderExpanded
          : null,
      child: SliverScrollViewCalendar(
        initialDate: widget.initialDate,
        beginningRangeDate: widget.beginningRangeDate,
        endingRangeDate: widget.endingRangeDate,
        state: widget.state,
        location: widget.location,
        view: widget.view,
        monthHeader: widget.monthHeader,
        initialScrollOffset: widget.initialScrollOffset,
      ),
    );
  }
}

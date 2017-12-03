/**
  * datetimeformat provides parsing and formatting for std.datetime objects.
  *
  * The format is taken from strftime:
  *    %a     The abbreviated name of the day of the week.
  *    %A     The full name of the day of the week.
  *    %b     The abbreviated month name.
  *    %B     The full month name.
  *    %C     The century number (year/100) as a 2-digit integer.
  *    %d     The day of the month as a decimal number (range 01 to 31).
  *    %e     Like %d, the day of the month as a decimal number, but space padded.
  *    %F     Equivalent to %Y-%m-%d (the ISO 8601 date format).
  *    %h     The hour as a decimal number using a 12-hour clock (range 01 to 12).
  *    %H     The hour as a decimal number using a 24-hour clock (range 00 to 23).
  *    %I     The hour as a decimal number using a 12-hour clock (range 00 to 23).
  *    %j     The day of the year as a decimal number (range 001 to 366).
  *    %k     The hour (24-hour clock) as a decimal number (range 0 to 23), space padded.
  *    %l     The hour (12-hour clock) as a decimal number (range 1 to 12), space padded.
  *    %m     The month as a decimal number (range 01 to 12).
  *    %M     The minute as a decimal number (range 00 to 59).
  *    %p     "AM" / "PM" (midnight is AM; noon is PM).
  *    %P     "am" / "pm" (midnight is AM; noon is PM).
  *    %r     Equivalent to "%I:%M:%S %p".
  *    %R     Equivalent to "%H:%M".
  *    %s     The number of seconds since the Epoch, 1970-01-01 00:00:00 +0000 (UTC).
  *    %S     The second as a decimal number (range 00 to 60).
  *    %T     Equivalent to "%H:%M:%S".
  *    %u     The day of the week as a decimal, range 1 to 7, Monday being 1 (formatting only).
  *    %V     The ISO 8601 week number (formatting only).
  *    %w     The day of the week as a decimal, range 0 to 6, Sunday being 0 (formatting only).
  *    %y     The year as a decimal number without a century (range 00 to 99).
  *    %Y     The year as a decimal number including the century, minimum 4 digits.
  *    %z     The +hhmm or -hhmm numeric timezone (that is, the hour and minute offset from UTC).
  *    %Z     The timezone name or abbreviation. Formatting only.
  *    %%     A literal '%' character.
  */
module pierce.datetimeformat;

import core.time;
import std.array;
import std.conv;
import std.datetime;
import std.string;
import std.utf : codeLength;
alias to = std.conv.to;


/**
 * Format the given datetime with the given format string.
 */
string format(SysTime dt, string formatString)
{
    Appender!string ap;
    bool inPercent;
    foreach (i, c; formatString)
    {
        if (inPercent)
        {
            inPercent = false;
            interpretIntoString(ap, dt, c);
        }
        else if (c == '%')
        {
            inPercent = true;
        }
        else
        {
            ap ~= c;
        }
    }
    return ap.data;
}


/**
 * Parse the given datetime string with the given format string.
 *
 * This tries rather hard to produce a reasonable result. If the format string doesn't describe an
 * unambiguous point time, the result will be a date that satisfies the inputs and should generally
 * be the earliest such date. However, that is not guaranteed.
 *
 * For instance:
 * ---
 * SysTime time = parse("%d", "21");
 * writeln(time);  // 0000-01-21T00:00:00.000000Z
 * ---
 */
SysTime parse(
        string data,
        string formatString,
        immutable(TimeZone) defaultTimeZone = null,
        bool allowTrailingData = false)
{
    auto a = Interpreter(data);
    auto res = a.parse(formatString, defaultTimeZone);
    if (res.error)
    {
        throw new Exception(res.error ~ " around " ~ res.remaining);
    }
    if (!allowTrailingData && res.remaining.length > 0)
    {
        throw new Exception("trailing data: " ~ res.remaining);
    }
    return res.dt;
}

/**
 * Try to parse the input string according to the given pattern.
 *
 * Return: true to indicate success; false to indicate failure
 */
bool tryParse(
        string data,
        string formatString,
        out SysTime dt,
        immutable(TimeZone) defaultTimeZone = null)
{
    auto a = Interpreter(data);
    auto res = a.parse(formatString, defaultTimeZone);
    if (res.error)
    {
        return false;
    }
    dt = res.dt;
    return true;
}

enum RFC1123FORMAT = "%a, %d %b %Y %H:%M:%S %.%.%.";
enum ISO8601FORMAT = "%Y-%m-%dT%H:%M:%S%z";

/** Parse an RFC1123 date. */
SysTime parseRFC1123(string data, bool allowTrailingData = false)
{
    return parse(data, RFC1123FORMAT, UTC(), allowTrailingData);
}

/** Produce an RFC1123 date string from a SysTime. */
string toRFC1123(SysTime date)
{
    return format(date.toUTC(), RFC1123FORMAT);
}

private:


immutable(TimeZone) utc;
static this() { utc = UTC(); }

enum weekdayNames = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
];

enum weekdayAbbrev = [
    "Sun",
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat"
];

enum monthNames = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];

enum monthAbbrev = [
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
];

struct Result
{
    SysTime dt;
    string error;
    string remaining;
    string remainingFormat;
}

// TODO support wstring, dstring
struct Interpreter
{
    this(string data)
    {
        this.data = data;
    }
    string data;

    int year;
    int century;
    int yearOfCentury;
    Month month;
    int dayOfWeek;
    int dayOfMonth;
    int dayOfYear;
    int isoWeek;
    int hour12;
    int hour24;
    int hour;
    int minute;
    int second;
    int nanosecond;
    int weekNumber;
    Duration tzOffset;
    string tzAbbreviation;
    string tzName;
    long epochSecond;
    enum AMPM { AM, PM, None };
    AMPM amPm = AMPM.None;

    Result parse(string formatString, immutable(TimeZone) defaultTimeZone)
    {
        auto tz = defaultTimeZone is null ? utc : defaultTimeZone;
        bool inPercent;
        foreach (size_t i, dchar c; formatString)
        {
            if (inPercent)
            {
                inPercent = false;
                if (!interpretFromString(c))
                {
                    auto remainder = data;
                    if (remainder.length > 15)
                    {
                        remainder = remainder[0..15];
                    }
                    return Result(SysTime.init, "unexpected value", data, formatString[i..$]);
                }
            }
            else if (c == '%')
            {
                inPercent = true;
            }
            else
            {
                // TODO non-ASCII
                auto b = data;
                bool endedEarly = false;
                foreach (size_t i, dchar dc; b)
                {
                    data = b[i..$];
                    if (i > 0)
                    {
                        endedEarly = true;
                        break;
                    }
                    if (c != dc)
                    {
                        return Result(SysTime.init, "unexpected literal", data, formatString[i..$]);
                    }
                }
                if (!endedEarly) data = "";
            }
        }

        if (!year)
        {
            year = century * 100 + yearOfCentury;
        }
        if (hour12)
        {
            if (amPm == AMPM.PM)
            {
                hour24 = (hour12 + 12) % 24;
            }
            else
            {
                hour24 = hour12;
            }
        }
        auto dt = SysTime(
                DateTime(year, month, dayOfMonth, hour24, minute, second),
                tz);
        return Result(dt, null, data);
    }

    bool interpretFromString(dchar c)
    {
        switch (c)
        {
            case '.':
                // TODO unicodes
                if (data.length >= 1)
                {
                    data = data[1..$];
                    return true;
                }
                return false;
            case 'a':
                foreach (i, m; weekdayAbbrev)
                {
                    if (data.startsWith(m))
                    {
                        data = data[m.length .. $];
                        return true;
                    }
                }
                return false;
            case 'A':
                foreach (i, m; weekdayNames)
                {
                    if (data.startsWith(m))
                    {
                        data = data[m.length .. $];
                        return true;
                    }
                }
                return false;
            case 'b':
                foreach (i, m; monthAbbrev)
                {
                    if (data.startsWith(m))
                    {
                        month = cast(Month)(i + 1);
                        data = data[m.length .. $];
                        return true;
                    }
                }
                return false;
            case 'B':
                foreach (i, m; monthNames)
                {
                    if (data.startsWith(m))
                    {
                        month = cast(Month)(i + 1);
                        data = data[m.length .. $];
                        return true;
                    }
                }
                return false;
            case 'C':
                return parseInt!(x => century = x)(data);
            case 'd':
                return parseInt!(x => dayOfMonth = x)(data);
            case 'e':
                return parseInt!(x => dayOfMonth = x)(data);
            case 'F':
                auto dash1 = data.indexOf('-');
                if (dash1 <= 0) return false;
                if (dash1 >= data.length - 1) return false;
                auto yearStr = data[0..dash1];
                auto year = yearStr.to!int;
                data = data[dash1 + 1 .. $];

                if (data.length < 5)
                {
                    // Month is 2 digits; day is 2 digits; dash between
                    return false;
                }
                if (data[2] != '-')
                {
                    return false;
                }
                if (!parseInt!(x => month = cast(Month)x)(data)) return false;
                if (!data.startsWith("-")) return false;
                data = data[1..$];
                return parseInt!(x => dayOfMonth = x)(data);
            case 'H':
            case 'k':
                auto h = parseInt!(x => hour24 = x)(data);
                return h;
            case 'h':
            case 'I':
            case 'l':
                return parseInt!(x => hour12 = x)(data);
            case 'j':
                return parseInt!(x => dayOfYear = x, 3)(data);
            case 'm':
                return parseInt!(x => month = cast(Month)x)(data);
            case 'M':
                return parseInt!(x => minute = x)(data);
            case 'p':
                if (data.startsWith("AM"))
                {
                    amPm = AMPM.AM;
                }
                else if (data.startsWith("PM"))
                {
                    amPm = AMPM.PM;
                }
                else
                {
                    return false;
                }
                return true;
            case 'P':
                if (data.startsWith("am"))
                {
                    amPm = AMPM.AM;
                }
                else if (data.startsWith("pm"))
                {
                    amPm = AMPM.PM;
                }
                else
                {
                    return false;
                }
                return true;
            case 'r':
                return interpretFromString('I') &&
                    pop(':') &&
                    interpretFromString('M') &&
                    pop(':') &&
                    interpretFromString('S') &&
                    pop(' ') &&
                    interpretFromString('p');
            case 'R':
                return interpretFromString('H') &&
                    pop(':') &&
                    interpretFromString('M');
            case 's':
                size_t end = 0;
                foreach (i2, c2; data)
                {
                    if (c2 < '0' || c2 > '9')
                    {
                        end = cast()i2;
                        break;
                    }
                }
                if (end == 0) return false;
                epochSecond = data[0..end].to!int;
                data = data[end..$];
                return true;
            case 'S':
                return parseInt!(x => second = x)(data);
            case 'T':
                return interpretFromString('H') &&
                    pop(':') &&
                    interpretFromString('M') &&
                    pop(':') &&
                    interpretFromString('S');
            case 'u':
                return parseInt!(x => dayOfWeek = cast(DayOfWeek)(x % 7))(data);
            case 'V':
                return parseInt!(x => isoWeek = x)(data);
            case 'y':
                return parseInt!(x => yearOfCentury = x)(data);
            case 'Y':
                size_t end = 0;
                foreach (i2, c2; data)
                {
                    if (c2 < '0' || c2 > '9')
                    {
                        end = i2;
                        break;
                    }
                }
                if (end == 0) return false;
                year = data[0..end].to!int;
                data = data[end..$];
                return true;
            case 'z':
                if (pop('Z'))  // for ISO8601
                {
                    tzOffset = 0.seconds;
                    return true;
                }

                int sign = 0;
                if (pop('-'))
                {
                    sign = -1;
                }
                else if (pop('+'))
                {
                    sign = 1;
                }
                else
                {
                    return false;
                }
                int hour, minute;
                parseInt!(x => hour = x)(data);
                parseInt!(x => minute = x)(data);
                tzOffset = dur!"minutes"(sign * (minute + 60 * hour));
                return true;
            case 'Z':
                // Oh god.
                // This could be something like America/Los_Angeles.
                // Or UTC.
                // Or EST5EDT.
                // And it could be followed by anything. Like the format might be:
                //  "%Z%a" -> America/Los_AngelesMon
                // I'll assume that this is followed by a space or something.
                return parseInt!(x => isoWeek = x)(data);
            default:
                throw new Exception("unrecognized control character %" ~ c.to!string);
        }
    }

    bool pop(dchar c)
    {
        if (data.startsWith(c))
        {
            data = data[c.codeLength!char .. $];
            return true;
        }
        return false;
    }
}

bool parseInt(alias setter, int length = 2)(ref string data)
{
    if (data.length < length)
    {
        return false;
    }
    auto c = data[0..length].strip;
    data = data[length..$];
    int v;
    try
    {
        v = c.to!int;

    }
    catch (ConvException e)
    {
        return false;
    }
    cast(void)setter(c.to!int);
    return true;
}

void interpretIntoString(ref Appender!string ap, SysTime dt, char c)
{
    switch (c)
    {
        case 'a':
            ap ~= weekdayAbbrev[cast(size_t)dt.dayOfWeek];
            return;
        case 'A':
            ap ~= weekdayNames[cast(size_t)dt.dayOfWeek];
            return;
        case 'b':
            ap ~= monthAbbrev[cast(size_t)dt.month];
            return;
        case 'B':
            ap ~= monthNames[cast(size_t)dt.month];
            return;
        case 'C':
            ap ~= (dt.year / 100).to!string;
            return;
        case 'd':
            auto s = dt.day.to!string;
            if (s.length == 1)
            {
                ap ~= "0";
            }
            ap ~= s;
            return;
        case 'e':
            auto s = dt.day.to!string;
            if (s.length == 1)
            {
                ap ~= " ";
            }
            ap ~= s;
            return;
        case 'F':
            interpretIntoString(ap, dt, 'Y');
            ap ~= '-';
            interpretIntoString(ap, dt, 'm');
            ap ~= '-';
            interpretIntoString(ap, dt, 'd');
            return;
        case 'g':
            // TODO what is this?
            throw new Exception("%g not yet implemented");
        case 'G':
            // TODO what is this?
            throw new Exception("%G not yet implemented");
        case 'h':
        case 'I':
            auto h = dt.hour;
            if (h == 0)
            {
                h = 12;
            }
            else if (h > 12)
            {
                h -= 12;
            }
            ap.pad(h.to!string, '0', 2);
            return;
        case 'H':
            ap.pad(dt.hour.to!string, '0', 2);
            return;
        case 'j':
            ap.pad(dt.dayOfYear.to!string, '0', 3);
            return;
        case 'k':
            ap.pad(dt.hour.to!string, ' ', 2);
            return;
        case 'l':
            auto h = dt.hour;
            if (h == 0)
            {
                h = 12;
            }
            else if (h > 12)
            {
                h -= 12;
            }
            ap.pad(h.to!string, ' ', 2);
            return;
        case 'm':
            uint m = cast(uint)dt.month;
            ap.pad(m.to!string, '0', 2);
            return;
        case 'M':
            ap.pad(dt.minute.to!string, '0', 2);
            return;
        case 'p':
            if (dt.hour >= 12)
            {
                ap ~= "PM";
            }
            else
            {
                ap ~= "AM";
            }
            return;
        case 'P':
            if (dt.hour >= 12)
            {
                ap ~= "pm";
            }
            else
            {
                ap ~= "am";
            }
            return;
        case 'r':
            interpretIntoString(ap, dt, 'I');
            ap ~= ':';
            interpretIntoString(ap, dt, 'M');
            ap ~= ':';
            interpretIntoString(ap, dt, 'S');
            ap ~= ' ';
            interpretIntoString(ap, dt, 'p');
            return;
        case 'R':
            interpretIntoString(ap, dt, 'H');
            ap ~= ':';
            interpretIntoString(ap, dt, 'M');
            return;
        case 's':
            auto delta = dt - SysTime(DateTime(1970, 1, 1), UTC());
            ap ~= delta.total!"seconds"().to!string;
            return;
        case 'S':
            ap.pad(dt.second.to!string, '0', 2);
            return;
        case 'T':
            interpretIntoString(ap, dt, 'H');
            ap ~= ':';
            interpretIntoString(ap, dt, 'M');
            ap ~= ':';
            interpretIntoString(ap, dt, 'S');
            return;
        case 'u':
            auto dow = cast(uint)dt.dayOfWeek;
            if (dow == 0) dow = 7;
            ap ~= dow.to!string;
            return;
        case 'w':
            ap ~= (cast(uint)dt.dayOfWeek).to!string;
            return;
        case 'y':
            ap.pad((dt.year % 100).to!string, '0', 2);
            return;
        case 'Y':
            ap.pad(dt.year.to!string, '0', 4);
            return;
        case 'z':
            import std.math : abs;
            auto d = dt.utcOffset;
            if (d < dur!"seconds"(0))
            {
                ap ~= '-';
            }
            else
            {
                ap ~= '+';
            }
            auto minutes = abs(d.total!"minutes");
            ap.pad((minutes / 60).to!string, '0', 2);
            ap.pad((minutes % 60).to!string, '0', 2);
            return;
        case 'Z':
            if (dt.dstInEffect)
            {
                ap ~= dt.timezone.stdName;
            }
            else if (dt.timezone is null)
            {
                ap ~= 'Z';
            }
            else
            {
                ap ~= dt.timezone.dstName;
            }
            return;
        case '%':
            ap ~= '%';
            return;
        default:
            throw new Exception("format element %" ~ c ~ " not recognized");
    }
}

void pad(ref Appender!string ap, string s, char pad, uint length)
{
    if (s.length >= length)
    {
        ap ~= s;
        return;
    }
    for (uint i = 0; i < length - s.length; i++)
    {
        ap ~= pad;
    }
    ap ~= s;
}

unittest
{
    import std.stdio;
    auto dt = SysTime(
            DateTime(2017, 5, 3, 14, 31, 57),
            UTC());
    auto isoishFmt = "%Y-%m-%d %H:%M:%S %z";
    auto isoish = dt.format(isoishFmt);
    assert(isoish == "2017-05-03 14:31:57 +0000", isoish);
    auto parsed = isoish.parse(isoishFmt);
    assert(parsed.timezone !is null);
    assert(parsed.timezone == UTC());
    assert(parsed == dt, parsed.format(isoishFmt));
}

unittest
{
    import std.stdio;
    auto dt = SysTime(
            DateTime(2017, 5, 3, 14, 31, 57),
            UTC());
    auto isoishFmt = ISO8601FORMAT;
    auto isoish = "2017-05-03T14:31:57Z";
    auto parsed = isoish.parse(isoishFmt);
    assert(parsed.timezone !is null);
    assert(parsed.timezone == UTC());
    assert(parsed == dt, parsed.format(isoishFmt));
}

unittest
{
    auto formatted = "Thu, 04 Sep 2014 06:42:22 GMT";
    auto dt = parseRFC1123(formatted);
    assert(dt == SysTime(DateTime(2014, 9, 4, 6, 42, 22), UTC()), dt.toISOString());
}

// Copyright (c) 2017 Matthew Brennan Jones <matthew.brennan.jones@gmail.com>
// Boost Software License - Version 1.0
// Get web browser history with the D programming language
// https://github.com/workhorsy/d-web-browser-history

/++
Get web browser history with the D programming language

Home page:
$(LINK https://github.com/workhorsy/d-web-browser-history)

Version: 1.2.0

License:
Boost Software License - Version 1.0

Examples:
----
import web_browser_history;
import std.stdio : stdout;

foreach (browser ; web_browser_history.getInstalledBrowsers()) {
	web_browser_history.readHistory(browser, delegate(string url, int visit_count) {
		stdout.writefln("browser:%s, url:%s, count:%s", browser, url, visit_count);
	});
}
----
+/


module web_browser_history;

import derelict.sqlite3.sqlite;

/++
The supported web browsers.

----
enum WebBrowser {
	Brave,
	Chrome,
	Chromium,
	Firefox,
	Opera,
}
----
+/

enum WebBrowser {
	Brave,
	Chrome,
	Chromium,
	Firefox,
	Opera,
}

private void delegate(string url, int visit_count) g_each_row_cb;

private static string[] black_list = [
	"bank", "credit union", "bond", "invest", "hospital", "medical", "private",
	"account"
];

private extern (C) int callback(void* NotUsed, int argc, char** argv, char** azColName) {
	import std.conv : to;
	import std.algorithm : any, count;
	import std.string : fromStringz;

	string url = (cast(string) fromStringz(argv[0] ? argv[0] : "NULL")).dup;
	auto visit_count = cast(string) fromStringz(argv[1] ? argv[1] : "0");
	int total = to!int(visit_count);

	bool is_black_listed = black_list.any!(entry => url.count(entry) > 0);

	if (! is_black_listed) {
		g_each_row_cb(url, total);
	}
	return 0;
}

private string[] getHistoryPaths(WebBrowser browser) {
	version (unittest) {
		final switch (browser) {
			case WebBrowser.Firefox:
				return getHistoryPaths("firefox_history.sqlite", ["test_browser_data"]);
			case WebBrowser.Chrome:
				return getHistoryPaths("chrome_history.sqlite", ["test_browser_data"]);
			case WebBrowser.Chromium:
				return getHistoryPaths("chromium_history.sqlite", ["test_browser_data"]);
			case WebBrowser.Opera:
				return getHistoryPaths("opera_history.sqlite", ["test_browser_data"]);
			case WebBrowser.Brave:
				return getHistoryPaths("brave_history.sqlite", ["test_browser_data"]);
		}
	} else {
		final switch (browser) {
			case WebBrowser.Firefox:
				return getHistoryPaths("places.sqlite", ["~/.mozilla/firefox/", "%APPDATA%/Mozilla/Firefox/"]);
			case WebBrowser.Chrome:
				return getHistoryPaths("History", ["~/.config/google-chrome/", "%LOCALAPPDATA%/Google/Chrome/"]);
			case WebBrowser.Chromium:
				return getHistoryPaths("History", ["~/.config/chromium/"]);
			case WebBrowser.Opera:
				return getHistoryPaths("History", ["~/.config/opera/", "%APPDATA%/Opera Software/Opera Stable/"]);
			case WebBrowser.Brave:
				return getHistoryPaths("History", ["~/.config/brave/", "%APPDATA%/brave/"]);
		}
	}
}

private string[] getHistoryPaths(string file_name, string[] settings_paths) {
	import std.file : exists, DirIterator, dirEntries, FileException;
	import std.path : baseName, SpanMode;

	string[] paths;
	foreach (settings_path; settings_paths) {
		string full_path = expandPath(settings_path);

		if (! exists(full_path)) {
			continue;
		}

		try {
			DirIterator iter = dirEntries(full_path, SpanMode.breadth, true);
			foreach (string path; iter) {
				if (baseName(path) == file_name) {
					paths ~= path;
				}
			}
		} catch (FileException) {
			// NOTE: Ignore any FS errors from dirEntries throwing
		}
	}

	return paths;
}

private string expandPath(string path) {
	import std.process : environment;
	import std.path : expandTilde;
	import std.algorithm : count;
	import std.string : replace;

	path = expandTilde(path);
	foreach (string name, string value ; environment.toAA()) {
		if (path.count(name) > 0) {
			path = path.replace("%" ~ name ~ "%", value);
		}
	}
	return path;
}

/++
Returns an array of installed web browsers.
+/
WebBrowser[] getInstalledBrowsers() {
	import std.traits : EnumMembers;

	// Get the installed browsers
	WebBrowser[] browsers;
	foreach (browser ; EnumMembers!WebBrowser) {
		if (getHistoryPaths(browser).length > 0) {
			browsers ~= browser;
		}
	}

	// Use firefox as the default browser, if none are installed
	if (browsers.length == 0) {
		browsers ~= WebBrowser.Firefox;
	}

	return browsers;
}

///
unittest {
	import derelict.sqlite3.sqlite : DerelictSQLite3;
	DerelictSQLite3.load();
	WebBrowser[] browsers = web_browser_history.getInstalledBrowsers();

	// browsers output
	// [Brave, Chrome, Chromium, Firefox, Opera]
}

/++
Reads all the history for the selected web browser.

Params:
 browser = The web browser to search
 each_row_cb = The callback to fire for each row in the history.
+/
void readHistory(WebBrowser browser, void delegate(string url, int visit_count) each_row_cb) {
	import std.stdio : stdout, stderr;
	import std.file : exists, remove, copy;
	import std.string : fromStringz;
	import std.string : toStringz;
	stdout.writefln("!!! readHistory"); stdout.flush();

	g_each_row_cb = each_row_cb;

	string[] paths = getHistoryPaths(browser);
	stdout.writefln("!!! paths: %s", paths); stdout.flush();
	string sql_query;
	final switch (browser) {
		case WebBrowser.Firefox:
			sql_query = "select url, visit_count from moz_places where hidden=0;";
			break;
		case WebBrowser.Chrome:
		case WebBrowser.Chromium:
		case WebBrowser.Opera:
		case WebBrowser.Brave:
			sql_query = "select url, visit_count from urls where hidden=0;";
			break;
	}

	immutable string uri = "History.sqlite";

	foreach (path; paths) {
		stdout.writefln("!!! path: %s", path); stdout.flush();

		// Copy the browser's history file to the local directory
		if (exists(uri)) {
			remove(uri);
		}
		copy(path, uri);
		stdout.writefln("!!! copy"); stdout.flush();

		sqlite3* db;
		char* zErrMsg;

		// Open the database
		int rc = sqlite3_open(uri.toStringz, &db);
		stdout.writefln("!!! sqlite3_open"); stdout.flush();
		if (rc != SQLITE_OK) {
			stderr.writefln("Can't open database: %s\n", cast(string) fromStringz(sqlite3_errmsg(db)));
			sqlite3_close(db);
			return;
		}

		// Read the database
		rc = sqlite3_exec(db, sql_query.toStringz, &callback, cast(void*) 0, &zErrMsg);
		stdout.writefln("!!! sqlite3_exec"); stdout.flush();
		if (rc != SQLITE_OK) {
			stderr.writefln("SQL error: %s\n", cast(string) fromStringz(zErrMsg));
			sqlite3_free(zErrMsg);
			return;
		}

		sqlite3_close(db);
		stdout.writefln("!!! sqlite3_close"); stdout.flush();
	}

	if (exists(uri)) {
		remove(uri);
	}
}

///
unittest {
	import derelict.sqlite3.sqlite : DerelictSQLite3;
	DerelictSQLite3.load();

	int[string] data;
	web_browser_history.readHistory(WebBrowser.Chrome, delegate(string url, int visit_count) {
		data[url] = visit_count;
	});

	// data output
	// ["https://dlang.org/":3, "https://www.google.com/":7, "https://www.reddit.com/":1]
}

/++
Reads all the history for all the web browsers.

Params:
 each_row_cb = The callback to fire for each row in the history.
+/
void readHistoryAll(void delegate(string url, int visit_count) each_row_cb) {
	import std.traits : EnumMembers;

	foreach (browser ; EnumMembers!WebBrowser) {
		readHistory(browser, each_row_cb);
	}
}

///
unittest {
	import derelict.sqlite3.sqlite : DerelictSQLite3;
	DerelictSQLite3.load();

	int[string] data;
	web_browser_history.readHistoryAll(delegate(string url, int visit_count) {
		data[url] = visit_count;
	});

	// data output
	// ["https://dlang.org/":3, "https://www.google.com/":7, "https://www.reddit.com/":1, "https://slashdot.org/":7]
}




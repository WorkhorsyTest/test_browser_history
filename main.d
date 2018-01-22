
int main() {
	import web_browser_history;
	import std.stdio : stdout;
	import derelict.sqlite3.sqlite : DerelictSQLite3;

	DerelictSQLite3.load();

	foreach (browser; web_browser_history.getInstalledBrowsers()) {
		stdout.writefln("browser:%s", browser);
		web_browser_history.readHistory(browser, delegate(string url, int visit_count) {
			//stdout.writefln("browser:%s, url:%s, count:%s", browser, url, visit_count);
		});
	}

	return 0;
}

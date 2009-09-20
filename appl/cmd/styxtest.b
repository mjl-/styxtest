implement Styxtest;

include "sys.m";
	sys: Sys;
	sprint: import sys;
	Qid, Dir: import sys;
	QTDIR, QTAPPEND, QTEXCL, QTAUTH, QTTMP, QTFILE: import sys;
	DMDIR, DMAPPEND, DMEXCL, DMAUTH, DMTMP: import sys;
include "draw.m";
include "arg.m";
include "styx.m";
	styx: Styx;
	Rmsg, Tmsg: import styx;
include "util0.m";
	util: Util0;
	l2a, fail, warn, p32: import util;

Styxtest: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};


dflag: int;
addr: string;

styxfd: ref Sys->FD;
msize: int;

createfile,
createdir:	string;
unremovablefile,
unremovabledir:	array of string;
nosuchfile:	array of string;
file,
filero,
filew,
filex,
filenoperm,
filenonempty,
dir,
dirw:	array of string;

path(s: string): array of string
{
	return l2a(sys->tokenize(s, "/").t1);
}

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	styx = load Styx Styx->PATH;
	styx->init();
	util = load Util0 Util0->PATH;
	util->init();

	arg->init(args);
	arg->setusage(arg->progname()+" [-d] addr [key value ...]");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args % 2 != 1)
		arg->usage();
	addr = hd args;
	for(args = tl args; args != nil; args = tl tl args) {
		a := hd tl args;
		case hd args {
		"createfile" =>	createfile = a;
		"createdir" =>	createdir = a;
		"unremovablefile" =>	unremovablefile = path(a);
		"unremovabledir" =>	unremovabledir = path(a);
		"nosuchfile" =>	nosuchfile = path(a);
		"file" =>	file = path(a);
		"filero" =>	filero = path(a);
		"filew" =>	filew = path(a);
		"filex" =>	filex = path(a);
		"filenoperm" =>	filenoperm = path(a);
		"filenonempty" =>	filenonempty = path(a);
		"dir" =>	dir = path(a);
		"dirw" =>	dirw = path(a);
		* =>	arg->usage();
		}
	}


	fid: int;
	(fid, msize, styxfd) = edialattach();
	bogusfid := fid+1;
	tag := 1;
	warn("sending bogus fid in messages, expecting failure");
	rerror(ref Tmsg.Walk (tag, bogusfid, bogusfid+1, array[0] of string));
	rerror(ref Tmsg.Open (tag, bogusfid, Styx->OREAD));
	rerror(ref Tmsg.Create (tag, bogusfid, "bogus", 8r666, Styx->OWRITE));
	rerror(ref Tmsg.Read (tag, bogusfid, big 0, 1));
	rerror(ref Tmsg.Write (tag, bogusfid, big 0, array[1] of byte));
	rerror(ref Tmsg.Clunk (tag, bogusfid));
	rerror(ref Tmsg.Stat (tag, bogusfid));
	rerror(ref Tmsg.Remove (tag, bogusfid));
	rerror(ref Tmsg.Wstat (tag, bogusfid, sys->nulldir));
	styxfd = nil;

	header("sending Version with normal tag, not NOTAG");
	styxfd = edial();
	rpcmsize(styxfd, ref Tmsg.Version (0, Styx->MAXRPC, Styx->VERSION), Styx->MAXRPC);
	styxfd = nil;

	header("sending Version with msize 0");
	styxfd = edial();
	pick r := rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, 0, Styx->VERSION), Styx->MAXRPC) {
	Version =>	warn("remote accepts msize 0, which is smaller than message headers");
	Error =>	;
	* =>		fail("bogus response");
	}
	styxfd = nil;

	header("sending Version with msize 1");
	styxfd = edial();
	pick r := rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, 1, Styx->VERSION), Styx->MAXRPC) {
	Version =>	warn("remote accepts msize 1, which is smaller than message headers");
	Error =>	;
	* =>		fail("bogus response");
	}
	styxfd = nil;

	header("sending Version with msize 8");
	styxfd = edial();
	pick r := rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, 8, Styx->VERSION), Styx->MAXRPC) {
	Version =>	warn("remote accepts msize 8, which is smaller than a Rmsg.Error");
	Error =>	;
	* =>		fail("bogus response");
	}
	styxfd = nil;

	if(0) {
		header("sending Version with small msize, then Attach to which response is larger than msize");
		styxfd = edial();
		atfid := 1;
		authfid := Styx->NOFID;
		at := ref Tmsg.Attach (0, atfid, authfid, "", "");
		smallmsize := at.packedsize();
		pick r := rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, smallmsize, Styx->VERSION), Styx->MAXRPC) {
		Version =>
			if(smallmsize < 0)
				fail(sprint("remote wanted even smaller msize %d, cannot do that", r.msize));
			warn(sprint("have small msize %d", smallmsize));
			rpcmsize(styxfd, at, smallmsize);
			rpcmsize(styxfd, ref Tmsg.Stat (0, atfid), smallmsize);
		Error =>	;
		* =>		fail("bogus response");
		}
		styxfd = nil;
	}

	header("sending Version with bogus version string");
	styxfd = edial();
	rv := pickversion(rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, Styx->MAXRPC, "bogus"), Styx->MAXRPC));
	if(rv.version != "unknown")
		fail(sprint("expected Rversion with version 'unknown', saw %#q", rv.version));
	styxfd = nil;

	header("sending Version with version 9P2000.bogus");
	styxfd = edial();
	rv = pickversion(rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, Styx->MAXRPC, "9P2000.bogus"), Styx->MAXRPC));
	if(rv.version != "9P2000")
		fail(sprint("expected Rversion with version '9P2000', saw %#q", rv.version));
	styxfd = nil;

	header("sending Version with 9P2001");
	styxfd = edial();
	rv = pickversion(rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, Styx->MAXRPC, "9P2001"), Styx->MAXRPC));
	if(rv.version != "9P2000")
		fail(sprint("expected Rversion with version '9P2000' in response to 9P2001, saw %#q", rv.version));
	styxfd = nil;

	header("sending Version with 9P1999");
	styxfd = edial();
	rv = pickversion(rpcmsize(styxfd, ref Tmsg.Version (Styx->NOTAG, Styx->MAXRPC, "9P1999"), Styx->MAXRPC));
	if(rv.version != "unknown")
		fail(sprint("expected Rversion with version 'unknown' in response to 9P1999, saw %#q", rv.version));
	styxfd = nil;

	header("flushing tag that's not pending (which is fine)");
	atfid: int;
	(atfid, msize, styxfd) = edialattach();
	nfid := atfid+1;
	rflush(ref Tmsg.Flush (0, 1));

	if(nosuchfile != nil) {
		header("walk to non-existent name");
		rerror(ref Tmsg.Walk (0, atfid, nfid, nosuchfile));
	}

	if(nosuchfile != nil) {
		header("walk to non-existent name, then try to clunk it (should fail)");
		rerror(ref Tmsg.Walk (0, atfid, nfid, nosuchfile));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(file != nil) {
		header("walk to existent name, then clunk it, should succeed.  then clunk again, should fail.");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		rclunk(ref Tmsg.Clunk (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	header("walk to invalid name (slashes, others).  that or file doesn't exist");
	rerror(ref Tmsg.Walk (0, atfid, nfid, array[] of {"a/b/c"}));
	rerror(ref Tmsg.Walk (0, atfid, nfid, array[] of {""}));

	header("clone fid by walking to 0 elems.  then clunk to verify it worked");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("clone fid by walking to 0 elems.  then clunk to verify it worked");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rclunk(ref Tmsg.Clunk (0, nfid));

	if(file != nil) {
		header("clone fid by walking to 0 elems.  then do fid-in-place walk  (and clunk to verify)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		rwalk(ref Tmsg.Walk (0, nfid, nfid, file));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	header("clone fid by walking to 0 elems, to itself");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rwalk(ref Tmsg.Walk (0, nfid, nfid, array[0] of string));
	rclunk(ref Tmsg.Clunk (0, nfid));
	rerror(ref Tmsg.Clunk (0, nfid));

	if(file != nil) {
		header("walk from non-directory");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		rerror(ref Tmsg.Walk (0, nfid, nfid, array[] of {".."}));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	header("walk from attach point to .");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[] of {"."}));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("walk to in-use new fid (invalid)");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rerror(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("clone by walk from an open directory (invalid)");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
	rerror(ref Tmsg.Walk (0, nfid, nfid+1, array[0] of string));
	rclunk(ref Tmsg.Clunk (0, nfid));

	if(file != nil) {
		header("in-place walk from an open directory (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rerror(ref Tmsg.Walk (0, nfid, nfid, file));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(file != nil) {
		header("clone walk from an open directory (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rerror(ref Tmsg.Walk (0, nfid, nfid+1, file));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filenonempty != nil) {
		header("open,pread n=1 off=0,pread n=1 off=1,pread n=0 off=0,pread n=0 off=1clunk");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filenonempty));
		ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rr := rread(ref Tmsg.Read (0, nfid, big 0, 1));
		if(len rr.data > 1) fail("long response");
		rr = rread(ref Tmsg.Read (0, nfid, big 1, 1));
		if(len rr.data > 1) fail("long response");
		rr = rread(ref Tmsg.Read (0, nfid, big 0, 0));
		if(len rr.data > 0) fail("long response");
		rr = rread(ref Tmsg.Read (0, nfid, big 1, 0));
		if(len rr.data > 0) fail("long response");
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filex != nil) {
		header("open, with OEXEC (like OREAD)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filex));
		ropen(ref Tmsg.Open (0, nfid, Styx->OEXEC));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filenoperm != nil) {
		header("open, bogus bits ~(OEXEC|OTRUNC|ORCLOSE)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filenoperm));
		rerror(ref Tmsg.Open (0, nfid, ~(Styx->OEXEC|Styx->OTRUNC|Styx->ORCLOSE)));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(0 && filero != nil) {
		# xxx is this really invalid?
		header("open, OREAD with OTRUNC");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filero));
		rerror(ref Tmsg.Open (0, nfid, Styx->OREAD|Styx->OTRUNC));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filenoperm != nil) {
		header("open, OREAD without permission");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filenoperm));
		rerror(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(file != nil) {
		header("open, from an open fid (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rerror(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	header("create, bad name (slash)");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rerror(ref Tmsg.Create (0, nfid, "/", 8r777|Styx->DMDIR, Styx->ORDWR));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("create, bad name (empty)");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rerror(ref Tmsg.Create (0, nfid, "", 8r777|Styx->DMDIR, Styx->ORDWR));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("create, bad name (.)");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rerror(ref Tmsg.Create (0, nfid, ".", 8r777|Styx->DMDIR, Styx->ORDWR));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("create, bad name (..)");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	rerror(ref Tmsg.Create (0, nfid, "..", 8r777|Styx->DMDIR, Styx->ORDWR));
	rclunk(ref Tmsg.Clunk (0, nfid));

	if(createfile != nil) {
		header("create, bad mode");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		rerror(ref Tmsg.Create (0, nfid, createfile, 8r666, ~(Styx->OEXEC|Styx->OTRUNC|Styx->ORCLOSE)));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(createfile != nil) {
		header("create file, remove, ensure fid is gone");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		rcreate(ref Tmsg.Create (0, nfid, createfile, 8r666, Styx->ORDWR));
		rremove(ref Tmsg.Remove (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(createdir != nil) {
		header("create directory for writing (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		rerror(ref Tmsg.Create (0, nfid, createdir, 8r777|Styx->DMDIR, Styx->OWRITE));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(createdir != nil) {
		header("create directory, remove");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		rcreate(ref Tmsg.Create (0, nfid, createdir, 8r777|Styx->DMDIR, Styx->OREAD));
		rremove(ref Tmsg.Remove (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(createfile != nil) {
		header("create file from an open fid (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
		ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rerror(ref Tmsg.Create (0, nfid, createfile, 8r666, Styx->ORDWR));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(file != nil) {
		header("open,read limbo-negative offset");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
		rread(ref Tmsg.Read (0, nfid, ~big 0, 1));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	header("open,read directory at bogus offset 1");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
	rerror(ref Tmsg.Read (0, nfid, big 1, 1024));
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("open,read directory at offset 0, plus next read");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
	rr := rread(ref Tmsg.Read (0, nfid, big 0, 1024));
	checkreaddir(rr.data);
	rr = rread(ref Tmsg.Read (0, nfid, big len rr.data, 1024));
	checkreaddir(rr.data);
	rclunk(ref Tmsg.Clunk (0, nfid));

	header("open,read directory at offset 0, rewind to offset 0");
	rwalk(ref Tmsg.Walk (0, atfid, nfid, array[0] of string));
	ropen(ref Tmsg.Open (0, nfid, Styx->OREAD));
	rr = rread(ref Tmsg.Read (0, nfid, big 0, 1024));
	checkreaddir(rr.data);
	rr = rread(ref Tmsg.Read (0, nfid, big 0, 1024));
	checkreaddir(rr.data);
	rclunk(ref Tmsg.Clunk (0, nfid));

	if(filew != nil) {
		header("open,write at beginning of file, then at offset 1");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filew));
		ropen(ref Tmsg.Open (0, nfid, Styx->OWRITE));
		rwrite(ref Tmsg.Write (0, nfid, big 0, array of byte "this is a test\n"));
		rwrite(ref Tmsg.Write (0, nfid, big 1, array of byte "his is a test\n"));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	# xxx this one is tricky, might for some fs'es take lots of memory/disk.  plus, there is a good chance this is invalid for the fs.
	if(0 && filew != nil) {
		header("open,write at limbo-negative offset");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filew));
		ropen(ref Tmsg.Open (0, nfid, Styx->OWRITE));
		rwrite(ref Tmsg.Write (0, nfid, ~big 0, array of byte "this is a test\n"));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(file != nil) {
		warn("clunk, open/closed fid for file");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		rclunk(ref Tmsg.Clunk (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));

		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		ropen(ref Tmsg.Open (0, nfid, Sys->OREAD));
		rclunk(ref Tmsg.Clunk (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}
		
	if(dir != nil) {
		warn("clunk, open/closed fid for file");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dir));
		rclunk(ref Tmsg.Clunk (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));

		rwalk(ref Tmsg.Walk (0, atfid, nfid, dir));
		ropen(ref Tmsg.Open (0, nfid, Sys->OREAD));
		rclunk(ref Tmsg.Clunk (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(file != nil) {
		warn("stat, open/closed fid for file");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		rs := rstat(ref Tmsg.Stat (0, nfid));
		rclunk(ref Tmsg.Clunk (0, nfid));
		if(rs.stat.mode & Styx->DMDIR) fail("file with DMDIR set");

		rwalk(ref Tmsg.Walk (0, atfid, nfid, file));
		ropen(ref Tmsg.Open (0, nfid, Sys->OREAD));
		rs = rstat(ref Tmsg.Stat (0, nfid));
		rclunk(ref Tmsg.Clunk (0, nfid));
		if(rs.stat.mode & Styx->DMDIR) fail("file with DMDIR set");
	}

	if(dir != nil) {
		warn("stat, open/closed fid for dir");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dir));
		rs := rstat(ref Tmsg.Stat (0, nfid));
		rclunk(ref Tmsg.Clunk (0, nfid));
		if((rs.stat.mode & Styx->DMDIR) == 0) fail("dir with DMDIR clear");

		rwalk(ref Tmsg.Walk (0, atfid, nfid, dir));
		ropen(ref Tmsg.Open (0, nfid, Sys->OREAD));
		rs = rstat(ref Tmsg.Stat (0, nfid));
		rclunk(ref Tmsg.Clunk (0, nfid));
		if((rs.stat.mode & Styx->DMDIR) == 0) fail("dir with DMDIR clear");
	}

	if(unremovablefile != nil) {
		header("remove, ensure unopened file fid is gone on error");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, unremovablefile));
		rerror(ref Tmsg.Remove (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(unremovablefile != nil) {
		header("remove, ensure opened file fid is gone on error");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, unremovablefile));
		ropen(ref Tmsg.Open (0, nfid, Sys->OREAD));
		rerror(ref Tmsg.Remove (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(unremovabledir != nil) {
		header("remove, ensure unopened dir fid is gone on error");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, unremovabledir));
		rerror(ref Tmsg.Remove (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(unremovabledir != nil) {
		header("remove, ensure opened dir fid is gone on error");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, unremovabledir));
		ropen(ref Tmsg.Open (0, nfid, Sys->OREAD));
		rerror(ref Tmsg.Remove (0, nfid));
		rerror(ref Tmsg.Clunk (0, nfid));
	}

	if(0 && dirw != nil) {
		header("wstat, null to commit to disk, on dir");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dirw));
		rwstat(ref Tmsg.Wstat (0, nfid, Sys->nulldir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filew != nil) {
		header("wstat, null to commit to disk, on file");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filew));
		rwstat(ref Tmsg.Wstat (0, nfid, Sys->nulldir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(dirw != nil) {
		header("wstat, rename to existing file");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dirw));
		rwalk(ref Tmsg.Walk (0, atfid, nfid+1, dirw));
		rcreate(ref Tmsg.Create (0, nfid, "file0", 8r666, Styx->OWRITE));
		rcreate(ref Tmsg.Create (0, nfid+1, "file1", 8r666, Styx->OWRITE));
		ndir := Sys->nulldir;
		ndir.name = "file1";
		rerror(ref Tmsg.Wstat (0, nfid, ndir));
		rremove(ref Tmsg.Remove (0, nfid));
		rremove(ref Tmsg.Remove (0, nfid+1));
	}

	if(filew != nil) {
		header("wstat, change from file to directory (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filew));
		rs := rstat(ref Tmsg.Stat (0, nfid));
		if(rs.stat.mode & Styx->DMDIR) fail("file has DMDIR set?");
		ndir := Sys->nulldir;
		ndir.mode = rs.stat.mode^Styx->DMDIR;;
		rerror(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(dirw != nil) {
		header("wstat, change from directory to file (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dirw));
		rs := rstat(ref Tmsg.Stat (0, nfid));
		if((rs.stat.mode & Styx->DMDIR) == 0) fail("dir has DMDIR clear?");
		ndir := Sys->nulldir;
		ndir.mode = rs.stat.mode^Styx->DMDIR;;
		rerror(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(dirw != nil) {
		header("wstat, changing name and back");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dirw));
		ndir := Sys->nulldir;
		ndir.name = "testdirw0";
		rwstat(ref Tmsg.Wstat (0, nfid, ndir));
		ndir.name = "testdirw";
		rwstat(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(dirw != nil) {
		header("wstat, changing mtime,atime on dir");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dirw));
		ndir := Sys->nulldir;
		ndir.atime = 123;
		ndir.mtime = 123;
		rwstat(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filew != nil) {
		header("wstat, changing mtime,atime on file");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filew));
		ndir := Sys->nulldir;
		ndir.atime = 123;
		ndir.mtime = 123;
		rwstat(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filew != nil) {
		header("wstat of DMAUTH on normal file (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, filew));
		ndir := Sys->nulldir;
		ndir.mode = Styx->DMDIR;
		rerror(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	if(filew != nil) {
		header("wstat of length on dir (invalid)");
		rwalk(ref Tmsg.Walk (0, atfid, nfid, dirw));
		ndir := Sys->nulldir;
		ndir.length = big 123;
		rerror(ref Tmsg.Wstat (0, nfid, ndir));
		rclunk(ref Tmsg.Clunk (0, nfid));
	}

	styxfd = nil;

	buf: array of byte;
	n: int;

	(atfid, msize, styxfd) = edialattach();
	header("writing bogus message type");
	buf = array[5] of byte;
	p32(buf, 0, big 10);
	buf[4] = byte 1;
	if(sys->write(styxfd, buf, len buf) != len buf)
		fail(sprint("write: %r"));
	n = sys->readn(styxfd, buf = array[64*1024] of byte, len buf);
	if(n > 0)
		fail("got response for bogus tmsg?");
	styxfd = nil;

	(atfid, msize, styxfd) = edialattach();
	header("writing bogus message, huge size");
	buf = array[5] of byte;
	p32(buf, 0, ~big 0);
	buf[4] = byte 1;
	if(sys->write(styxfd, buf, len buf) != len buf)
		fail(sprint("write: %r"));
	n = sys->readn(styxfd, buf = array[64*1024] of byte, len buf);
	if(n > 0)
		fail("got response for bogus tmsg?");
	styxfd = nil;
}

checkreaddir(d: array of byte)
{
	o := 0;
	while(o < len d) {
		(n, stat) := styx->unpackdir(d[o:]);
		if(n < 0)
			fail("invalid Dir");
		if(n == 0)
			fail("incomplete Dir");
		o += n;
		warn("\t"+styx->dir2text(stat));
		checkdir(stat);
	}
}

edial(): ref Sys->FD
{
	(ok, conn) := sys->dial(addr, nil);
	if(ok != 0)
		fail(sprint("dial %q: %r", addr));
	return conn.dfd;
}

edialattach(): (int, int, ref Sys->FD)
{
	fd := edial();

	ms := Styx->MAXRPC;
	pick r := rpcmsize(fd, ref Tmsg.Version (Styx->NOTAG, Styx->MAXRPC, Styx->VERSION), ms) {
	Version =>	ms = r.msize;
	* =>	fail("bad response to Version");
	}

	atfid := 1;
	authfid := Styx->NOFID;
	user := "none";
	spec := "";
	pick r := rpcmsize(fd, ref Tmsg.Attach (0, atfid, authfid, user, spec), ms) {
	Attach =>	;
	* =>	fail("bad response to Attach");
	}

	return (atfid, ms, fd);
}

rpc(t: ref Tmsg): ref Rmsg
{
	ewrite(styxfd, t);
	pick r := rm := readmsg(styxfd, msize) {
	Version =>
		msize = r.msize;
	}
	return rm;
}

rpcmsize(fd: ref Sys->FD, t: ref Tmsg, ms: int): ref Rmsg
{
	ewrite(fd, t);
	return readmsg(fd, ms);
}

ewrite(fd: ref Sys->FD, t: ref Tmsg)
{
	warn("-> "+t.text());
	buf := t.pack();
	if(sys->write(fd, buf, len buf) != len buf)
		fail(sprint("write: %r"));
}

readmsg(fd: ref Sys->FD, ms: int): ref Rmsg
{
	rm := Rmsg.read(fd, ms);
	if(rm == nil)
		fail(sprint("eof from remote"));
	pick r := rm {
	Readerror =>
		fail("error reading: "+r.error);
	}

	warn("<- "+rm.text());

	pick r := rm {
	Version =>
		;
	Auth =>
		if(r.aqid.qtype != Sys->QTAUTH)
			fail("auth qid not QTAUTH");
	Attach =>
		if(r.qid.qtype & ~(QTDIR|QTAPPEND|QTEXCL|QTAUTH|QTTMP|QTTMP))
			fail(sprint("bogus bits in qtype set, qtype %#ux", r.qid.qtype));
		if(r.qid.qtype == Sys->QTAUTH)
			fail("attach returned qid with QTAUTH");
		if((r.qid.qtype & Sys->QTDIR) == 0)
			fail("attach returned qid without QTDIR");
		if(r.qid.qtype & QTAPPEND)
			fail("attach returned QTAPPEND for dir");
	Flush =>
		;
	Error =>
		;
	Clunk or
	Remove or
	Wstat =>
		;
	Walk =>
		for(i := 0; i < len r.qids; i++)
			checkqid("walk", r.qids[i]);
	Open =>
		checkqid("open", r.qid);
	Create =>
		checkqid("create", r.qid);
	Read =>
		;
	Write =>
		;
	Stat =>
		checkdir(r.stat);
	}
	return rm;
}

checkdir(d: Dir)
{
	if(d.name == nil)
		fail("stat gave empty dir.name");
	if(d.uid == nil)
		fail("stat gave empty dir.uid");
	if(d.gid == nil)
		fail("stat gave empty dir.gid");
	checkqid("stat", d.qid);
	if(d.mode & ~(DMDIR|DMAPPEND|DMEXCL|DMAUTH|DMTMP|8r777))
		fail(sprint("stat gave bogus bits in dir.mode %#ux", d.mode));
	if((d.mode & (DMDIR|DMAPPEND)) == (DMDIR|DMAPPEND))
		fail(sprint("stat gave DMDIR|DMAPPEND in dir.mode"));
	dmdir := (d.mode & DMDIR) != 0;
	qtdir := (d.qid.qtype & QTDIR) != 0;
	if(dmdir ^ qtdir)
		fail(sprint("stat's qid.qtype %#ux and d.mode %#ux do not agree on QTDIR and DMDIR", d.qid.qtype, d.mode));
}

checkqid(name: string, q: Qid)
{
	if(q.qtype & ~(QTDIR|QTAPPEND|QTEXCL|QTAUTH|QTTMP|QTTMP))
		fail(sprint("%s returned bogus bits in qtype set, qtype %#ux", name, q.qtype));
	if(q.qtype == Sys->QTAUTH)
		fail(sprint("%s returned q with QTAUTH", name));
	if((q.qtype & (QTDIR|QTAPPEND)) == (QTDIR|QTAPPEND))
		fail(sprint("%s returned QTAPPEND for dir", name));
}

pickversion(mm: ref Rmsg): ref Rmsg.Version
{
	pick m := mm {Version => return m;}
	fail("unexpected response");
	return nil;
}

rversion(tm: ref Tmsg.Version): ref Rmsg.Version
{
	pick m := rpc(tm) {Version => return m;}
	fail("unexpected response");
	return nil;
}

rauth(tm: ref Tmsg.Auth): ref Rmsg.Auth
{
	pick m := rpc(tm) {Auth => return m;}
	fail("unexpected response");
	return nil;
}

rattach(tm: ref Tmsg.Attach): ref Rmsg.Attach
{
	
	pick m := rpc(tm) {Attach => return m;}
	fail("unexpected response");
	return nil;
}

rflush(tm: ref Tmsg.Flush): ref Rmsg.Flush
{
	pick m := rpc(tm) {Flush => return m;}
	fail("unexpected response");
	return nil;
}

rwalk(tm: ref Tmsg.Walk): ref Rmsg.Walk
{
	pick m := rpc(tm) {Walk => return m;}
	fail("unexpected response");
	return nil;
}

ropen(tm: ref Tmsg.Open): ref Rmsg.Open
{
	pick m := rpc(tm) {Open => return m;}
	fail("unexpected response");
	return nil;
}

rcreate(tm: ref Tmsg.Create): ref Rmsg.Create
{
	pick m := rpc(tm) {Create => return m;}
	fail("unexpected response");
	return nil;
}

rread(tm: ref Tmsg.Read): ref Rmsg.Read
{
	pick m := rpc(tm) {Read => return m;}
	fail("unexpected response");
	return nil;
}

rwrite(tm: ref Tmsg.Write): ref Rmsg.Write
{
	pick m := rpc(tm) {Write => return m;}
	fail("unexpected response");
	return nil;
}

rclunk(tm: ref Tmsg.Clunk): ref Rmsg.Clunk
{
	pick m := rpc(tm) {Clunk => return m;}
	fail("unexpected response");
	return nil;
}

rstat(tm: ref Tmsg.Stat): ref Rmsg.Stat
{
	pick m := rpc(tm) {Stat => return m;}
	fail("unexpected response");
	return nil;
}

rremove(tm: ref Tmsg.Remove): ref Rmsg.Remove
{
	pick m := rpc(tm) {Remove => return m;}
	fail("unexpected response");
	return nil;
}

rwstat(tm: ref Tmsg.Wstat): ref Rmsg.Wstat
{
	pick m := rpc(tm) {Wstat => return m;}
	fail("unexpected response");
	return nil;
}

rerror(tm: ref Tmsg): ref Rmsg.Error
{
	pick m := rpc(tm) {Error => return m;}
	fail("unexpected response");
	return nil;
}

header(s: string)
{
	warn("");
	warn(s);
}

say(s: string)
{
	if(dflag)
		warn(s);
}

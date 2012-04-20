/**
	File handling.

	Copyright: © 2012 Sönke Ludwig
	License: Subject to the terms of the MIT license, as written in the included LICENSE.txt file.
	Authors: Sönke Ludwig
*/
module vibe.core.file;

import vibe.core.log;
import vibe.stream.stream;

import std.algorithm;
import std.exception;
import std.string;

version(Posix){
	import core.sys.posix.fcntl;
	import core.sys.posix.sys.stat;
	import core.sys.posix.unistd;
}
version(Windows){
	import std.c.windows.stat;

	private {
		extern(C){
			alias long off_t;
			int open(in char* name, int mode);
			int chmod(in char* name, int mode);
			int close(int fd);
			int read(int fd, void *buffer, uint count);
			int write(int fd, in void *buffer, uint count);
			off_t lseek(int fd, off_t offset, int whence);
		}
		
		enum O_RDONLY = 0;
		enum O_WRONLY = 1;
	    enum O_APPEND = 8;
	    enum O_CREAT = 0x0100;
	    enum O_TRUNC = 0x0200;

		enum _S_IREAD = 0x0100;          /* read permission, owner */
		enum _S_IWRITE = 0x0080;          /* write permission, owner */
		alias struct_stat stat_t;
	}
}

private {
	enum O_BINARY = 0x8000;
	enum SEEK_SET = 0;
	enum SEEK_CUR = 1;
	enum SEEK_END = 2;
}

enum FileMode {
	Read,
	CreateTrunc
}

FileStream openFile(string path, FileMode mode = FileMode.Read)
{
	return new FileStream(path, mode);
}

class FileStream : Stream {
	private {
		int m_fileDescriptor;
		ulong m_size;
		ulong m_ptr = 0;
		FileMode m_mode;
	}
	
	protected this(string path, FileMode mode)
	{
		m_mode = mode;
		if( mode == FileMode.Read )
			m_fileDescriptor = open(path.toStringz(), O_RDONLY|O_BINARY);
		else
			m_fileDescriptor = open(path.toStringz(), O_WRONLY|O_CREAT|O_TRUNC|O_BINARY);
		if( m_fileDescriptor < 0 )
			throw new Exception("Failed to open '"~path~"' for reading.");
			
		version(linux){
			// stat_t seems to be defined wrong on linux/64
			m_size = .lseek(m_fileDescriptor, 0, SEEK_END);
		} else {
			stat_t st;
			fstat(m_fileDescriptor, &st);
			m_size = st.st_size;
			
			// (at least) on windows, the created file is write protected
			version(Windows){
				if( mode == FileMode.CreateTrunc )
					chmod(path.toStringz(), S_IREAD|S_IWRITE);
			}
		}
		lseek(m_fileDescriptor, 0, SEEK_SET);
		
		logDebug("opened file %s with %d bytes as %d", path, m_size, m_fileDescriptor);
	}
	
	@property int fd() { return m_fileDescriptor; }
	@property ulong size() const { return m_size; }
	@property bool readable() const { return m_mode == FileMode.Read; }
	@property bool writable() const { return m_mode != FileMode.Read; }

	void seek(ulong offset)
	{
		enforce(.lseek(m_fileDescriptor, offset, SEEK_SET) == offset, "Failed to seek in file.");
		m_ptr = offset;
	}
	
	void close()
	{
		if( m_fileDescriptor != -1 ){
			.close(m_fileDescriptor);
			m_fileDescriptor = -1;
		}
	}

	@property bool empty() const { assert(this.readable); return m_ptr >= m_size; }
	@property ulong leastSize() const { assert(this.readable); return m_size - m_ptr; }

	void read(ubyte[] dst)
	{
		assert(this.readable);
		enforce(dst.length <= leastSize);
		enforce(.read(m_fileDescriptor, dst.ptr, dst.length) == dst.length, "Failed to read data from disk.");
		m_ptr += dst.length;
	}

	ubyte[] readLine(size_t max_bytes = 0, string linesep = "\r\n")
	{
		return readLineDefault(max_bytes, linesep);
	}

	ubyte[] readAll(size_t max_bytes = 0) { return readAllDefault(max_bytes); }


	void write(in ubyte[] bytes, bool do_flush = true)
	{
		assert(this.writable);
		enforce(.write(m_fileDescriptor, bytes.ptr, bytes.length) == bytes.length, "Failed to write data to disk.");
		m_ptr += bytes.length;
	}

	void write(InputStream stream, ulong nbytes = 0, bool do_flush = true)
	{
		writeDefault(stream, nbytes, do_flush);
	}

	void flush()
	{
		assert(this.writable);
	}

	void finalize()
	{
		flush();
	}
}

#include "mmap_file.h"  
  
#ifdef _WIN32  
  
#include <vector>  
  
#include "platform_win.h"  
  
#else  
  
#include <sys/mman.h>  
#include <sys/types.h>  
#include <sys/stat.h>  
#include <fcntl.h>  
#include <unistd.h>  
  
#endif  
  
#include <filesystem>  
  
#include "cata_scope_helpers.h"  
#include "cata_utility.h"  
  
#ifdef __clang__  
#define CLANG_REINITIALIZES [[clang::reinitializes]]  
#else  
#define CLANG_REINITIALIZES  
#endif  
  
mmap_file::mmap_file() = default;  
  
mmap_file::~mmap_file() = default;  
  
struct mmap_file::impl {  
    virtual bool resize_file( size_t desired_size ) = 0;  
    virtual bool flush( size_t offset, size_t length ) = 0;  
  
    virtual ~impl() = default;  
  
    virtual size_t len() const = 0;  
    virtual void *base() const = 0;  
};  
  
struct malloc_impl : mmap_file::impl {  
    explicit malloc_impl( size_t size ) {  
        if( ( base_ = malloc( size ) ) ) {  
            len_ = size;  
        }  
    }  
  
    CLANG_REINITIALIZES void reset() {  
        base_ = nullptr;  
        len_ = 0;  
    }  
  
    malloc_impl( malloc_impl &&rhs ) noexcept {  
        *this = std::move( rhs );  
        rhs.reset();  
    }  
  
    ~malloc_impl() override {  
        free( base_ );  
    }  
  
    malloc_impl &operator=( malloc_impl &&rhs ) = default;  
  
    // No copying  
    malloc_impl( const malloc_impl & ) = delete;  
    malloc_impl &operator=( const malloc_impl & ) = delete;  
  
    size_t len() const override {  
        return len_;  
    }  
  
    void *base() const override {  
        return base_;  
    }  
  
    bool resize_file( size_t desired_size ) override {  
        void *new_base = realloc( base_, desired_size );  
        if( new_base ) {  
            base_ = new_base;  
            len_ = desired_size;  
            return true;  
        }  
        return false;  
    }  
  
    bool flush( size_t, size_t ) override {  
        return true;  
    }  
  
    void *base_ = nullptr;  
    size_t len_ = 0;  
};  
  
struct file_impl : mmap_file::impl {  
#ifdef _WIN32  
    file_impl( HANDLE file, bool writeable ) : writeable { writeable }, file { file} {}  
#else  
    file_impl( int file, bool writeable ) : writeable { writeable}, file { file } {}  
#endif  
    CLANG_REINITIALIZES void reset() {  
        writeable = false;  
        base_ = nullptr;  
        len_ = 0;  
#ifdef _WIN32  
        file = INVALID_HANDLE_VALUE;  
        file_mapping = NULL;  
#else  
        file = -1;  
#endif  
    }  
  
    file_impl( file_impl &&rhs ) noexcept {  
        *this = std::move( rhs );  
        rhs.reset();  
    }  
    file_impl &operator=( file_impl &&rhs ) = default;  
  
    // No copying  
    file_impl( const file_impl & ) = delete;  
    file_impl &operator=( const file_impl & ) = delete;  
  
    bool writeable = false;  
  
    void *base() const override {  
        return base_;  
    }  
  
    size_t len() const override {  
        return len_;  
    }  
  
    mutable void *base_ = nullptr;  
    size_t len_ = 0;  
  
#ifdef _WIN32  
    HANDLE file = INVALID_HANDLE_VALUE;  
    HANDLE file_mapping = NULL;  
  
    bool map_view() {  
        if( base_ != nullptr && len_ != 0 ) {  
            return true;  
        }  
        LARGE_INTEGER file_size{};  
        if( !GetFileSizeEx( file, &file_size ) ) {  
            // Failed to get file size.  
            return false;  
        }  
  
        if( file_size.QuadPart == 0 ) {  
            return false;  
        }  
  
        HANDLE file_mapping_handle = CreateFileMappingW(  
                                         file,  
                                         nullptr,  
                                         writeable ? PAGE_READWRITE : PAGE_READONLY,  
                                         file_size.HighPart,  
                                         file_size.LowPart,  
                                         nullptr  
                                     );  
        if( file_mapping_handle == NULL ) {  
            return false;  
        }  
        on_out_of_scope close_file_mapping_guard( [&] { CloseHandle( file_mapping_handle ); } );  
  
        void *map_base = MapViewOfFile(  
                             file_mapping_handle,  
                             ( writeable ? FILE_MAP_WRITE : 0 ) | FILE_MAP_READ,  
                             0,  
                             0,  
                             file_size.QuadPart  
                         );  
        if( map_base == nullptr ) {  
            // Failed to mmap file.  
            return false;  
        }  
        close_file_mapping_guard.cancel();  
        file_mapping = file_mapping_handle;  
        base_ = map_base;  
        len_ = file_size.QuadPart;  
        return true;  
    }  
  
    bool unmap_view() {  
        bool success = true;  
        if( base_ != nullptr ) {  
            if( !UnmapViewOfFile( base_ ) ) {  
                success = false;  
            }  
        }  
        base_ = nullptr;  
        len_ = 0;  
        if( file_mapping != NULL ) {  
            if( !CloseHandle( file_mapping ) ) {  
                success = false;  
            }  
        }  
        file_mapping = NULL;  
        return success;  
    }  
  
    ~file_impl() override {  
        unmap_view();  
        if( file != INVALID_HANDLE_VALUE ) {  
            CloseHandle( file );  
        }  
    }  
#else  
    int file = -1;  
  
#ifdef __EMSCRIPTEN__  
    // Emscripten's __mmap_js does not support writeable MAP_SHARED file  
    // mappings and crashes with "Cannot read properties of null (reading  
    // 'buffer')". Emulate the mapping by reading the whole file into a heap  
    // buffer, and write any changes back to disk in flush()/unmap_view().  
    bool flush_to_disk( size_t offset, size_t length ) {  
        if( file == -1 || base_ == nullptr ) {  
            return false;  
        }  
        const char *src = reinterpret_cast<const char *>( base_ ) + offset;  
        size_t total_written = 0;  
        while( total_written < length ) {  
            ssize_t w = pwrite( file, src + total_written, length - total_written,  
                                offset + total_written );  
            if( w < 0 ) {  
                return false;  
            }  
            if( w == 0 ) {  
                break;  
            }  
            total_written += static_cast<size_t>( w );  
        }  
        return true;  
    }  
  
    bool map_view() {  
        if( base_ != nullptr && len_ != 0 ) {  
            return true;  
        }  
        struct stat buf {};  
        if( fstat( file, &buf ) ) {  
            return false;  
        }  
        size_t file_size = buf.st_size;  
        if( file_size == 0 ) {  
            return false;  
        }  
        void *heap = malloc( file_size );  
        if( heap == nullptr ) {  
            return false;  
        }  
        char *dst = reinterpret_cast<char *>( heap );  
        size_t total_read = 0;  
        while( total_read < file_size ) {  
            ssize_t r = pread( file, dst + total_read, file_size - total_read, total_read );  
            if( r < 0 ) {  
                free( heap );  
                return false;  
            }  
            if( r == 0 ) {  
                break;  
            }  
            total_read += static_cast<size_t>( r );  
        }  
        base_ = heap;  
        len_ = file_size;  
        return true;  
    }  
  
    bool unmap_view() {  
        bool success = true;  
        if( base_ != nullptr ) {  
            if( writeable ) {  
                success = flush_to_disk( 0, len_ );  
            }  
            free( base_ );  
        }  
        base_ = nullptr;  
        len_ = 0;  
        return success;  
    }  
#else  
    bool map_view() {  
        struct stat buf {};  
        if( fstat( file, &buf ) ) {  
            return false;  
        }  
        size_t file_size = buf.st_size;  
  
        void *map_base = mmap( nullptr, file_size, ( writeable ? PROT_WRITE : 0 ) | PROT_READ, MAP_SHARED,  
                               file, 0 );  
        if( map_base == MAP_FAILED ) {  
            return false;  
        }  
  
        base_ = map_base;  
        len_ = file_size;  
  
        return true;  
    }  
  
    bool unmap_view() {  
        if( base_ != nullptr ) {  
            munmap( base_, len_ );  
        }  
        base_ = nullptr;  
        len_ = 0;  
        return true;  
    }  
#endif  
    ~file_impl() override {  
        unmap_view();  
        if( file != -1 ) {  
            close( file );  
        }  
    }  
#endif  
  
    bool resize_file( size_t desired_size ) override {  
        if( desired_size == len() ) {  
            return true;  
        }  
        if( !unmap_view() ) {  
            return false;  
        }  
#ifdef _WIN32  
        LARGE_INTEGER file_size;  
        file_size.QuadPart = desired_size;  
        if( !SetFilePointerEx( file, file_size, NULL, FILE_BEGIN ) ) {  
            return false;  
        }  
        if( !SetEndOfFile( file ) ) {  
            return false;  
        }  
#else  
        if( ftruncate( file, desired_size ) ) {  
            return false;  
        }  
#endif  
  
        if( desired_size != 0 && !map_view() ) {  
            return false;  
        }  
        return true;  
    }  
  
    bool flush( size_t offset, size_t length ) override {  
        char *base_ptr = reinterpret_cast<char *>( base() ) + offset;  
#ifdef _WIN32  
        FlushViewOfFile( base_ptr, length );  
        FlushFileBuffers( file );  
#elif defined(__EMSCRIPTEN__)  
        ( void )base_ptr;  
        return flush_to_disk( offset, length );  
#else  
        // msync requires the base pointer to be rounded to a page boundary.  
        size_t page_offset = offset % 4096;  
        base_ptr -= page_offset;  
        length += page_offset;  
        msync( base_ptr, length, MS_SYNC );  
#endif  
        return true;  
    }  
};  
  
std::unique_ptr<mmap_file> mmap_file::map_file_generic(  
    const std::filesystem::path &file_path,  
    bool writeable )  
{  
    std::unique_ptr<mmap_file> mapped_file;  
  
#ifdef _WIN32  
    HANDLE file_handle;  
    file_handle = CreateFileW(  
                      file_path.native().c_str(),  
                      ( writeable ? GENERIC_WRITE : 0 ) | GENERIC_READ,  
                      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,  
                      nullptr,  
                      writeable ? OPEN_ALWAYS : OPEN_EXISTING,  
                      0,  
                      nullptr  
                  );  
  
    if( file_handle == INVALID_HANDLE_VALUE ) {  
        return mapped_file;  
    }  
#else  
    const std::string &file_path_string = file_path.native();  
    // 644 = User RW, Group R, Other R.  
    // Only used when creating a file. Ignored when file exists.  
    int perms = S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH;  
    int file_handle = open( file_path_string.c_str(), writeable ? O_CREAT | O_RDWR : O_RDONLY, perms );  
    if( file_handle == -1 ) {  
        return mapped_file;  
    }  
#endif  
    std::shared_ptr<file_impl> pimpl = std::make_shared<file_impl>( file_handle, writeable );  
    if( !pimpl->map_view() && !writeable ) {  
        return mapped_file;  
    }  
#if !defined(_WIN32) && !defined(__EMSCRIPTEN__)  
    if( !writeable ) {  
        close( pimpl->file );  
        pimpl->file = -1;  
    }  
#endif  
    mapped_file = std::unique_ptr<mmap_file> { new mmap_file() };  
    mapped_file->pimpl = std::move( pimpl );  
    return mapped_file;  
}  
  
std::shared_ptr<const mmap_file> mmap_file::map_file( const std::filesystem::path &file_path )  
{  
    return map_file_generic( file_path, false );  
}  
  
std::unique_ptr<mmap_file> mmap_file::map_writeable_file( const std::filesystem::path &file_path )  
{  
    return map_file_generic( file_path, true );  
}  
  
std::unique_ptr<mmap_file> mmap_file::map_writeable_memory( size_t initial_size )  
{  
    std::unique_ptr<mmap_file> memory_file{ new mmap_file() };  
    memory_file->pimpl = std::make_shared<malloc_impl>( initial_size );  
    return memory_file;  
}  
  
bool mmap_file::resize_file( size_t desired_size )  
{  
    return pimpl->resize_file( desired_size );  
}  
  
void *mmap_file::base()  
{  
    return pimpl->base();  
}  
  
void const *mmap_file::base() const  
{  
    return pimpl->base();  
}  
  
size_t mmap_file::len() const  
{  
    return pimpl->len();  
}  
  
void mmap_file::flush()  
{  
    flush( 0, len() );  
}  
  
void mmap_file::flush( size_t offset, size_t length )  
{  
    if( !base() || !len() || offset + length > len() ) {  
        return;  
    }  
    pimpl->flush( offset, length );  
}

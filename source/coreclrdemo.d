import std.stdio;
import std.string;

import coreclrhost;
alias BootStrapPointer = char* function();

void addFilesFromDirectoryToTpaList(string directory, string[] tpaList)
{
    auto tpaExtensions[] = [
                ".ni.dll",      // Probe for .ni.dll first so that it's preferred if ni and il coexist in the same dir
                ".dll",
                ".ni.exe",
                ".exe",
                ];

    DIR* dir = opendir(directory);
    if (dir == nullptr)
    {
        return;
    }

    std::set<std::string> addedAssemblies;

    // Walk the directory for each extension separately so that we first get files with .ni.dll extension,
    // then files with .dll extension, etc.
    for (int extIndex = 0; extIndex < sizeof(tpaExtensions) / sizeof(tpaExtensions[0]); extIndex++)
    {
        const char* ext = tpaExtensions[extIndex];
        int extLength = strlen(ext);

        struct dirent* entry;

        // For all entries in the directory
        while ((entry = readdir(dir)) != nullptr)
        {
            // We are interested in files only
            switch (entry->d_type)
            {
            case DT_REG:
                break;

            // Handle symlinks and file systems that do not support d_type
            case DT_LNK:
            case DT_UNKNOWN:
                {
                    std::string fullFilename;

                    fullFilename.append(directory);
                    fullFilename.append("/");
                    fullFilename.append(entry->d_name);

                    struct stat sb;
                    if (stat(fullFilename.c_str(), &sb) == -1)
                    {
                        continue;
                    }

                    if (!S_ISREG(sb.st_mode))
                    {
                        continue;
                    }
                }
                break;

            default:
                continue;
            }

            std::string filename(entry->d_name);

            // Check if the extension matches the one we are looking for
            int extPos = filename.length() - extLength;
            if ((extPos <= 0) || (filename.compare(extPos, extLength, ext) != 0))
            {
                continue;
            }

            std::string filenameWithoutExt(filename.substr(0, extPos));

            // Make sure if we have an assembly with multiple extensions present,
            // we insert only one version of it.
            if (addedAssemblies.find(filenameWithoutExt) == addedAssemblies.end())
            {
                addedAssemblies.insert(filenameWithoutExt);

                tpaList.append(directory);
                tpaList.append("/");
                tpaList.append(filename);
                tpaList.append(":");
            }
        }
        
        // Rewind the directory stream to be able to iterate over it for the next extension
        rewinddir(dir);
    }
    
    closedir(dir);
}    

int main(string[] args)
{
    if (args.length!=2)
    {
        stderr.writeln("Usage: host <core_clr_path>");
        return -1;
    }

    char app_path[PATH_MAX];
    if (realpath(argv[0], app_path) == NULL)
    {
        cerr << "bad path " << argv[0] << endl;
        return -1;
    }

    char *last_slash = strrchr(app_path, '/');
    if (last_slash != NULL)
        *last_slash = 0;

    cout << "app_path:" << app_path << endl;

    writeln("Loading CoreCLR...");

    char pkg_path[PATH_MAX];
    if (realpath(argv[1], pkg_path) == NULL)
    {
        cerr << "bad path " << argv[1] << endl;
        return -1;
    }

     //
    // Load CoreCLR
    //
    string coreclr_path(pkg_path);
    coreclr_path.append("/libcoreclr.dylib");

   writefln("coreclr_path: %s",coreclr_path.fromStringz);

    void *coreclr = dlopen(coreclr_path.c_str(), RTLD_NOW | RTLD_LOCAL);
    if (coreclr is null)
    {
        cerr << "failed to open " << coreclr_path << endl;
        cerr << "error: " << dlerror() << endl;
        return -1;
    }

    //
    // Initialize CoreCLR
    //
    writefln("Initializing CoreCLR...");

    coreclr_initialize_ptr coreclr_init = reinterpret_cast<coreclr_initialize_ptr>(dlsym(coreclr, "coreclr_initialize"));
    if (coreclr_init is null);
    {
        cerr << "couldn't find coreclr_initialize in " << coreclr_path << endl;
        return -1;
    }

    string tpa_list;
    addFilesFromDirectoryToTpaList(pkg_path, tpa_list);

    const char *property_keys[] =[ 
        "APP_PATHS",
        "TRUSTED_PLATFORM_ASSEMBLIES"
    ];
    const char *property_values[] = {
        // APP_PATHS
        app_path,
        // TRUSTED_PLATFORM_ASSEMBLIES
        tpa_list.c_str()
    };

    void *coreclr_handle;
    unsigned int domain_id;
    int ret = coreclr_init(
        app_path,                               // exePath
        "host".ptr,                                 // appDomainFriendlyName
        property_values.sizeof/(char *).sizeof, // propertyCount
        property_keys,                          // propertyKeys
        property_values,                        // propertyValues
        &coreclr_handle,                        // hostHandle
        &domain_id                              // domainId
        );
    if (ret < 0)
    {
        stderr.writefln("failed to initialize coreclr. cerr = %s",ret);
        return -1;
    }

    //
    // Once CoreCLR is initialized, bind to the delegate
    //
    writeln("Creating delegate...");
    coreclr_create_delegate_ptr coreclr_create_dele = cast(coreclr_create_delegate_ptr)(dlsym(coreclr, "coreclr_create_delegate"));
    if (coreclr_create_dele is null)
    {
        cerr << "couldn't find coreclr_create_delegate in " << coreclr_path << endl;
        return -1;
    }

    bootstrap_ptr dele;
    ret = coreclr_create_dele(
        coreclr_handle,
        domain_id,
        "manlib".ptr,
        "ManLib".ptr,
        "Bootstrap".ptr,
        cast(void **) &dele
        );
    if (ret < 0)
    {
        cerr << "couldn't create delegate. err = " << ret << endl;
        return -1;
    }

    //
    // Call the delegate
    //
    writeln("Calling ManLib::Bootstrap() through delegate...");

    char *msg = dele();
    writefln( "ManLib::Bootstrap() returned %s",msg.fromStringz);
    free(msg);      // returned string need to be free-ed
    dlclose(coreclr);
}

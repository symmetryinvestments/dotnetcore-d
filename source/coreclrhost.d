module coreclr.binding;

// For each hosting API, we define a function prototype and a function pointer
// The prototype is useful for implicit linking against the dynamic coreclr
// library and the pointer for explicit dynamic loading (dlopen, LoadLibrary)
//
int coreclr_initialize(const char* exePath, const char* appDomainFriendlyName, int propertyCount, const char** propertyKeys, const char** propertyValues, void** hostHandle, uint* domainId);
int coreclr_shutdown(void* hostHandle, uint domainId);
int coreclr_shutdown_2(void* hostHandle, uint domainId, int* latchedExitCode);
int coreclr_create_delegate(void* hostHandle, uint domainId, const char* entryPointAssemblyName, const char* entryPointTypeName, const char* entryPointMethodName, void** dg);
int coreclr_execute_assembly( void* hostHandle, uint domainId, int argc, const char** argv, const char* managedAssemblyPath, uint* exitCode);

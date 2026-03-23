# Helpers Layer Plan

## Overview
The Helpers layer contains utility functions for formatting file system data for display. Currently consists of a single static utility enum.

## FormatHelpers (FormatHelpers.swift)

### Purpose
Centralized formatting utility providing standardized display formatting for file sizes, dates, and file type descriptions. Used by views (InspectorView, FileListView, StatusBarView) to present file metadata.

### Declaration
```swift
enum FormatHelpers  // Enum with no cases — namespace for static functions
```

### Static Formatters (Cached)
Three formatters are lazily initialized as static properties for reuse across calls:

| Formatter | Type | Configuration |
|-----------|------|---------------|
| byteCountFormatter | ByteCountFormatter | countStyle = .file |
| relativeDateFormatter | RelativeDateTimeFormatter | unitsStyle = .abbreviated |
| absoluteDateFormatter | DateFormatter | dateFormat = "MMM d, yyyy" |

### Functions

#### formatFileSize(_ bytes: Int64) -> String
Formats byte counts into human-readable file sizes using system conventions.
```
Input:  1_536_000
Output: "1.5 MB"
```
Uses ByteCountFormatter with `.file` count style (matches Finder formatting).

#### formatDate(_ date: Date) -> String
Intelligent date formatting with relative/absolute switching:
- **Within 7 days**: Relative format (e.g., "2 hours ago", "3 days ago")
- **Older than 7 days**: Absolute format (e.g., "Mar 15, 2024")

```swift
let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
if date > sevenDaysAgo {
    return relativeDateFormatter.localizedString(for: date, relativeTo: Date())
} else {
    return absoluteDateFormatter.string(from: date)
}
```

#### fileKindDescription(for url: URL) -> String
Returns human-readable file type description with multi-level fallback:

1. **Primary**: Query `typeIdentifierKey` from URL resource values → look up UTType → use `localizedDescription`
2. **Fallback 1**: Query `contentTypeKey` → use `localizedDescription`
3. **Fallback 2**: Derive from file extension via `UTType(filenameExtension:)` → use `localizedDescription`
4. **Fallback 3**: Return "Folder" (if directory) or "Document" (if file)

### Design Patterns

- **Static utility enum**: No instances, all static methods — prevents accidental instantiation
- **Lazy static formatters**: Created once, reused across all calls — avoids formatter allocation overhead
- **Fallback chains**: Multiple strategies for type detection ensure a result is always returned
- **System integration**: Uses Apple's ByteCountFormatter and RelativeDateTimeFormatter for locale-correct formatting

### Usage Locations
- **InspectorView**: File size, modification date, creation date, file kind
- **FileListView**: Date Modified column, Size column
- **StatusBarView**: Available disk space formatting

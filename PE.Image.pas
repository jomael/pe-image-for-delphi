unit PE.Image;

interface

uses
  System.Classes,
  System.SysUtils,
  System.Generics.Collections,

  PE.Common,
  PE.Headers,
  PE.DataDirectories,

  PE.Msg,
  PE.Utils,

  PE.Image.Defaults,
  PE.Image.Saving,

  PE.Types,
  PE.Types.DOSHeader,
  PE.Types.Directories,
  PE.Types.FileHeader,
  PE.Types.NTHeaders,
  PE.Types.Sections,
  PE.Types.Relocations,
  PE.Types.Imports,
  PE.Types.Export,

  PE.ExportSym,

  PE.TLS,
  PE.Section,
  PE.Sections,
  PE.Imports,
  PE.Resources,

  PE.Parser.Headers,
  PE.Parser.Export,
  PE.Parser.Import,
  PE.Parser.Relocs,
  PE.Parser.TLS,
  PE.Parser.Resources,

  PE.COFF,
  PE.COFF.Types,

  PE.MemoryStream;

type

  TPEImageKind = (PEIMAGE_KIND_DISK, PEIMAGE_KIND_MEMORY);

  { TPEImage }

  TPEImage = class
  private
    FImageKind: TPEImageKind;

    // Used only for loading from mapped image. Nil for disk images.
    FPEMemoryStream: TPEMemoryStream;

    FFileName: string;
    FFileSize: UInt64;
    FDefaults: TPEDefaults;

    FCOFF: TCOFF;

    FDosHeader: TImageDOSHeader; // DOS header.
    FLFANew: uint32;             // Address of new header next after DOS.
    FDosBlock: TBytes;           // Bytes between DOS header and next header.
    FSecHdrGap: TBytes;          // Gap after section headers.

    FFileHeader: TImageFileHeader;
    FOptionalHeader: TPEOptionalHeader;

    FSections: TPESections;
    FRelocs: TRelocs;
    FImports: TPEImports;
    FExports: TPEExportSyms;
    FExportedName: AnsiString;
    FTLS: TTLS;
    FResourceTree: TResourceTree;
    FOverlay: TOverlay;

    FParsers: array [TParserFlag] of TPEParserClass;
    FMsg: TMsgMgr;
    FPositionRVA: TRVA; // Current RVA.
    FDataDirectories: TDataDirectories;

    { Notifiers }
    procedure DoReadError;

    { Parsers }
    procedure InitParsers;

    { Base loading }
    function LoadSectionHeaders(AStream: TStream): UInt16;
    function LoadSectionData(AStream: TStream): UInt16;

    // Replace /%num% to name from COFF string table.
    procedure ResolveSectionNames;

    function GetImageBase: TRVA; inline;
    procedure SetImageBase(Value: TRVA); inline;

    function GetSizeOfImage: UInt64; inline;
    procedure SetSizeOfImage(Value: UInt64); inline;

    function EntryPointRVAGet: TRVA; inline;
    procedure EntryPointRVASet(Value: TRVA); inline;

    function FileAlignmentGet: uint32; inline;
    procedure FileAlignmentSet(const Value: uint32); inline;

    function SectionAlignmentGet: uint32; inline;
    procedure SectionAlignmentSet(const Value: uint32); inline;

    function GetFileHeader: PImageFileHeader; inline;
    function GetImageDOSHeader: PImageDOSHeader; inline;
    function GetOptionalHeader: PPEOptionalHeader; inline;

    function GetPositionVA: TVA;
    procedure SetPositionVA(const Value: TVA);

    procedure SetPositionRVA(const Value: TRVA);

  protected

    // If image is disk-based, result is created TFileStream.
    // If it's memory mapped, result is opened memory stream.
    function SourceStreamGet(Mode: word): TStream;

    // If image is disk-based, stream is freed.
    // If it's memory mapped, nothing happens.
    procedure SourceStreamFree(Stream: TStream);

  public

    // Create without message proc.
    constructor Create(); overload;

    // Create with message proc.
    constructor Create(AMsgProc: TMsgProc); overload;

    destructor Destroy; override;

    // Check if stream at offset Ofs is MZ/PE image.
    // Result is False if either failed to make check or it's not valid image.
    class function IsPE(AStream: TStream; Ofs: UInt64 = 0): boolean; overload; static;

    // Check if file is PE.
    class function IsPE(const FileName: string): boolean; overload; static;

    // Check if image is 32/64 bit.
    function Is32bit: boolean; inline;
    function Is64bit: boolean; inline;

    function IsDLL: boolean; inline;

    // Get image bitness. 32/64 or 0 if unknown.
    function GetImageBits: UInt16; inline;
    procedure SetImageBits(Value: UInt16);

    { PE Streaming }

    // Seek RVA or VA and return True on success.
    function SeekRVA(RVA: TRVA): boolean;
    function SeekVA(VA: TVA): boolean;

    // Read Count bytes to Buffer and return number of bytes read.
    function Read(Buffer: Pointer; Count: cardinal): uint32; overload;

    // Read Count bytes to Buffer and return True if all bytes were read.
    function ReadEx(Buffer: Pointer; Count: cardinal): boolean; overload; inline;

    // Skip Count bytes.
    procedure Skip(Count: integer);

    // Read 1-byte 0-terminated string.
    function ReadANSIString: RawByteString; overload;
    function ReadANSIString(out Value: RawByteString): RawByteString; overload;

    // Read 2-byte UTF-16 string with length prefix (2 bytes).
    function ReadUnicodeString: UnicodeString;

    // Reading values.
    // todo: these functions should be Endianness-aware.
    function ReadUInt8: UInt8; overload; inline;
    function ReadUInt16: UInt16; overload; inline;
    function ReadUInt32: uint32; overload; inline;
    function ReadUInt64: UInt64; overload; inline;
    function ReadUIntPE: UInt64; overload; inline; // 64/32 depending on PE format.

    function ReadUInt8(OutData: PUInt8): boolean; overload; inline;
    function ReadUInt16(OutData: PUInt16): boolean; overload; inline;
    function ReadUInt32(OutData: PUInt32): boolean; overload; inline;
    function ReadUInt64(OutData: PUInt64): boolean; overload; inline;
    function ReadUIntPE(OutData: PUInt64): boolean; overload; inline; // 64/32 depending on PE format.

    // Write Count bytes from Buffer to current position.
    function Write(Buffer: Pointer; Count: cardinal): uint32; overload;

    { Address conversions }

    // Check if RVA exists.
    function RVAExists(RVA: TRVA): boolean;

    // Convert RVA to memory pointer.
    function RVAToMem(RVA: TRVA): Pointer;

    // Convert RVA to file offset. OutOfs can be nil.
    function RVAToOfs(RVA: TRVA; OutOfs: PDword): boolean;

    // Find Section by RVA. OutSec can be nil.
    function RVAToSec(RVA: TRVA; OutSec: PPESection): boolean;

    // Convert RVA to VA.
    function RVAToVA(RVA: TRVA): TVA; inline;

    // Check if VA exists.
    function VAExists(VA: TRVA): boolean;

    // Convert VA to memory pointer.
    function VAToMem(VA: TVA): Pointer; inline;

    // Convert VA to file offset. OutOfs can be nil.
    function VAToOfs(VA: TVA; OutOfs: PDword): boolean; inline;

    // Find Section by VA. OutSec can be nil.
    function VAToSec(VA: TRVA; OutSec: PPESection): boolean;

    // Convert VA to RVA.
    function VAToRVA(VA: TVA): TRVA; inline;

    { Image }

    // Clear image.
    procedure Clear;

    // Calculate not aligned size of headers.
    function CalcHeadersSizeNotAligned: uint32; inline;

    // Calculate valid aligned size of image.
    function CalcVirtualSizeOfImage: UInt64; inline;

    // Calc raw size of image (w/o overlay), or 0 if failed.
    // Can be used if image loaded from stream and exact image size is unknown.
    // Though we still don't know overlay size.
    function CalcRawSizeOfImage: UInt64; inline;

    // Calc offset of section headers.
    function CalcSecHdrOfs: TFileOffset;

    // Calc offset of section headers end.
    function CalcSecHdrEndOfs: TFileOffset;

    // Calc size of optional header w/o directories.
    function CalcSizeOfPureOptionalHeader: uint32;

    // Set aligned SizeOfHeaders.
    procedure FixSizeOfHeaders; inline;

    // Set valid size of image.
    procedure FixSizeOfImage; inline;

    { Loading }

    // Load image from stream.
    function LoadFromStream(AStream: TStream;
      AParseStages: TParserFlags = DEFAULT_PARSER_FLAGS;
      ImageKind: TPEImageKind = PEIMAGE_KIND_DISK): boolean;

    // Load image from file.
    function LoadFromFile(const AFileName: string;
      AParseStages: TParserFlags = DEFAULT_PARSER_FLAGS): boolean;

    // Load image from image in memory. Won't help if image in memory has
    // spoiled headers.
    function LoadFromMappedImage(const AFileName: string;
      AParseStages: TParserFlags = DEFAULT_PARSER_FLAGS): boolean;

    { Saving }

    // Save image to stream.
    function SaveToStream(AStream: TStream): boolean;

    // Save image to file.
    function SaveToFile(const AFileName: string): boolean;

    { Sections }

    // Get last section containing raw offset and size.
    // Get nil if no good section found.
    function GetLastSectionWithValidRawData: TPESection;

    { Overlay }

    // Get overlay record pointer.
    function GetOverlay: POverlay;

    // Save overlay to file. It can be either appended to existing file or new
    // file will be created.
    function SaveOverlayToFile(const AFileName: string; Append: boolean = false): boolean;

    // Remove overlay from current image file.
    function RemoveOverlay: boolean;

    // Set overlay for current image file from file data of AFileName file.
    // If Offset and Size are 0, then whole file is appended.
    function LoadOverlayFromFile(const AFileName: string;
      Offset: UInt64 = 0; Size: UInt64 = 0): boolean; overload;

    { Writing to external stream }

    // Write buffer to stream.
    function StreamWrite(AStream: TStream; var Buf; Size: integer): boolean;

    // Write RVA to stream (32/64 bit sized depending on image).
    function StreamWriteRVA(AStream: TStream; RVA: TRVA): boolean;

    // Write 1-byte 0-terminated string.
    procedure StreamWriteStrA(AStream: TStream; const Str: RawByteString);

    { Dump }

    // Save memory region to stream/file (in section boundary).
    // Result is number of bytes written.
    // todo: maybe also add cross-section dumps.
    function DumpRegionToStream(AStream: TStream; RVA: TRVA; Size: uint32): uint32;
    function DumpRegionToFile(const AFileName: string; RVA: TRVA; Size: uint32): uint32;

    { Regions }

    procedure RegionRemove(RVA: TRVA; Size: uint32);

    { Properties }

    property Msg: TMsgMgr read FMsg;

    property Defaults: TPEDefaults read FDefaults;

    // Current read/write position.
    property PositionRVA: TRVA read FPositionRVA write SetPositionRVA;
    property PositionVA: TVA read GetPositionVA write SetPositionVA;

    property ImageKind: TPEImageKind read FImageKind;
    property FileName: string read FFileName;

    // Offset of NT headers, used building new image.
    property LFANew: uint32 read FLFANew write FLFANew;
    property DosBlock: TBytes read FDosBlock;
    property SecHdrGap: TBytes read FSecHdrGap;

    // Headers.
    property DOSHeader: PImageDOSHeader read GetImageDOSHeader;
    property FileHeader: PImageFileHeader read GetFileHeader;
    property OptionalHeader: PPEOptionalHeader read GetOptionalHeader;

    // Directories.
    property DataDirectories: TDataDirectories read FDataDirectories;

    // Image sections.
    property Sections: TPESections read FSections;

    // Relocations.
    property Relocs: TRelocs read FRelocs;

    // Import items.
    property Imports: TPEImports read FImports;

    // Export items.
    property ExportSyms: TPEExportSyms read FExports;

    // Image exported name.
    property ExportedName: AnsiString read FExportedName write FExportedName;

    // Thread Local Storage items.
    property TLS: TTLS read FTLS;

    // Resource items.
    property ResourceTree: TResourceTree read FResourceTree;

    property ImageBase: TRVA read GetImageBase write SetImageBase;
    property SizeOfImage: UInt64 read GetSizeOfImage write SetSizeOfImage;

    // 32/64
    property ImageBits: UInt16 read GetImageBits write SetImageBits;

    property EntryPointRVA: TRVA read EntryPointRVAGet write EntryPointRVASet;
    property FileAlignment: uint32 read FileAlignmentGet write FileAlignmentSet;
    property SectionAlignment: uint32 read SectionAlignmentGet write SectionAlignmentSet;

  end;

implementation

{ TPEImage }

function TPEImage.EntryPointRVAGet: TRVA;
begin
  Result := FOptionalHeader.AddressOfEntryPoint;
end;

procedure TPEImage.EntryPointRVASet(Value: TRVA);
begin
  FOptionalHeader.AddressOfEntryPoint := Value;
end;

function TPEImage.GetImageBase: TRVA;
begin
  Result := FOptionalHeader.ImageBase;
end;

procedure TPEImage.SetImageBase(Value: TRVA);
begin
  FOptionalHeader.ImageBase := Value;
end;

function TPEImage.GetSizeOfImage: UInt64;
begin
  Result := FOptionalHeader.SizeOfImage;
end;

procedure TPEImage.SetSizeOfImage(Value: UInt64);
begin
  FOptionalHeader.SizeOfImage := Value;
end;

function TPEImage.StreamWrite(AStream: TStream; var Buf; Size: integer): boolean;
begin
  Result := AStream.Write(Buf, Size) = Size;
end;

function TPEImage.StreamWriteRVA(AStream: TStream; RVA: TRVA): boolean;
var
  rva32: uint32;
  rva64: UInt64;
begin
  if Is32bit then
  begin
    rva32 := RVA;
    Result := AStream.Write(rva32, 4) = 4;
    exit;
  end;
  if Is64bit then
  begin
    rva64 := RVA;
    Result := AStream.Write(rva64, 8) = 8;
    exit;
  end;
  exit(false);
end;

procedure TPEImage.StreamWriteStrA(AStream: TStream; const Str: RawByteString);
const
  zero: byte = 0;
begin
  if Str <> '' then
    AStream.Write(Str[1], Length(Str));
  AStream.Write(zero, 1);
end;

constructor TPEImage.Create;
begin
  Create(nil);
end;

constructor TPEImage.Create(AMsgProc: TMsgProc);
begin
  FMsg := TMsgMgr.Create(AMsgProc);
  FDefaults := TPEDefaults.Create(self);

  FDataDirectories := TDataDirectories.Create(self);

  FSections := TPESections.Create(self);

  FRelocs := TRelocs.Create;

  FImports := TPEImports.Create;

  FExports := TPEExportSyms.Create;

  FTLS := TTLS.Create;

  FResourceTree := TResourceTree.Create;

  FCOFF := TCOFF.Create(self);

  InitParsers;

  FDefaults.SetAll;
end;

procedure TPEImage.Clear;
begin
  if FImageKind = PEIMAGE_KIND_MEMORY then
    raise Exception.Create('Can''t clear mapped in-memory image.');

  FLFANew := 0;
  SetLength(FDosBlock, 0);
  SetLength(FSecHdrGap, 0);

  FCOFF.Clear;
  FDataDirectories.Clear;
  FSections.Clear;
  FImports.Clear;
  FExports.Clear;
  FTLS.Clear;
  FResourceTree.Clear;
end;

destructor TPEImage.Destroy;
begin
  FPEMemoryStream.Free;
  FResourceTree.Free;
  FTLS.Free;
  FExports.Free;
  FImports.Free;
  FRelocs.Free;
  FSections.Free;
  FDataDirectories.Free;
  FCOFF.Free;
  inherited Destroy;
end;

procedure TPEImage.DoReadError;
begin
  raise Exception.Create('Read Error.');
end;

function TPEImage.DumpRegionToFile(const AFileName: string; RVA: TRVA;
  Size: uint32): uint32;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    Result := DumpRegionToStream(fs, RVA, Size);
  finally
    fs.Free;
  end;
end;

function TPEImage.DumpRegionToStream(AStream: TStream; RVA: TRVA;
  Size: uint32): uint32;
const
  BUFSIZE = 8192;
var
  Sec: TPESection;
  Ofs, TmpSize: uint32;
  pCur, pEnd: PByte;
begin
  Result := 0;

  if not RVAToSec(RVA, @Sec) then
    exit;

  Ofs := RVA - Sec.RVA;
  pCur := Sec.Mem + Ofs; // start from
  TmpSize := Sec.GetAllocatedSize;
  if (Ofs + Size) < TmpSize then
    TmpSize := Ofs + Size;
  pEnd := Sec.Mem + TmpSize;

  if pCur >= pEnd then
    exit;

  while (Size <> 0) do
  begin
    if Size >= BUFSIZE then
      TmpSize := BUFSIZE
    else
      TmpSize := Size;
    AStream.Write(pCur^, TmpSize);
    inc(pCur, TmpSize);
    dec(Size, TmpSize);
    inc(Result, TmpSize);
  end;
end;

procedure TPEImage.InitParsers;
begin
  FParsers[PF_EXPORT] := TPEExportParser;
  FParsers[PF_IMPORT] := TPEImportParser;
  FParsers[PF_RELOCS] := TPERelocParser;
  FParsers[PF_TLS] := TPETLSParser;
  FParsers[PF_RESOURCES] := TPEResourcesParser;
end;

function TPEImage.CalcHeadersSizeNotAligned: uint32;
begin
  Result := $400; // todo: do not hardcode
end;

procedure TPEImage.FixSizeOfHeaders;
begin
  FOptionalHeader.SizeOfHeaders :=
    AlignUp(CalcHeadersSizeNotAligned, FileAlignment);
end;

function TPEImage.CalcVirtualSizeOfImage: UInt64;
begin
  with FSections do
  begin
    if Count <> 0 then
      Result := AlignUp(Last.RVA + Last.VirtualSize, SectionAlignment)
    else
      Result := AlignUp(CalcHeadersSizeNotAligned, SectionAlignment);
  end;
end;

function TPEImage.CalcRawSizeOfImage: UInt64;
var
  Last: TPESection;
begin
  Last := GetLastSectionWithValidRawData;
  if (Last <> nil) then
    Result := Last.GetEndRawOffset
  else
    Result := 0;
end;

procedure TPEImage.FixSizeOfImage;
begin
  SizeOfImage := CalcVirtualSizeOfImage;
end;

function TPEImage.CalcSecHdrOfs: TFileOffset;
begin
{$WARN COMBINING_SIGNED_UNSIGNED OFF}
  Result := FLFANew + 4 + SizeOf(TImageFileHeader) +
    CalcSizeOfPureOptionalHeader + FDataDirectories.Count *
    SizeOf(TImageDataDirectory);
{$WARN COMBINING_SIGNED_UNSIGNED ON}
end;

function TPEImage.CalcSecHdrEndOfs: TFileOffset;
begin
  Result := CalcSecHdrOfs + FSections.Count * SizeOf(TImageSectionHeader);
end;

function TPEImage.CalcSizeOfPureOptionalHeader: uint32;
begin
  Result := FOptionalHeader.CalcSize(ImageBits);
end;

function TPEImage.GetFileHeader: PImageFileHeader;
begin
  Result := @self.FFileHeader;
end;

function TPEImage.LoadSectionHeaders(AStream: TStream): UInt16;
var
  Sec: TPESection;
  Cnt: integer;
begin
  Result := 0;

  Cnt := FFileHeader.NumberOfSections;

  FSections.Clear;

  while Result < Cnt do
  begin
    Sec := TPESection.Create;
    if not Sec.LoadHeaderFromStream(AStream, Result) then
    begin
      Sec.Free;
      break;
    end;

    if not Sec.IsNameSafe then
    begin
      Sec.Name := AnsiString(format('sec_%4.4x', [Result]));
      Msg.Write('Section has not safe name. Overriding to %s', [Sec.Name]);
    end;

    FSections.Add(Sec);
    inc(Result);
  end;

  // Check section count.
  if FSections.Count <> FFileHeader.NumberOfSections then
    FMsg.Write('Found %d of %d section headers.',
      [FSections.Count, FFileHeader.NumberOfSections]);
end;

function TPEImage.LoadSectionData(AStream: TStream): UInt16;
var
  i: integer;
  Sec: TPESection;
begin
  Result := 0;
  // todo: check if section overlaps existing sections.
  for i := 0 to FSections.Count - 1 do
  begin
    Sec := FSections[i];

    if FImageKind = PEIMAGE_KIND_DISK then
    begin
      if Sec.LoadDataFromStream(AStream) then
        inc(Result);
    end
    else
    begin
      if Sec.LoadDataFromStreamEx(AStream, Sec.RVA, Sec.VirtualSize) then
        inc(Result);
    end;
  end;
end;

procedure TPEImage.ResolveSectionNames;
var
  i, StringOfs, err: integer;
  Sec: TPESection;
  t: RawByteString;
begin
  for i := 0 to FSections.Count - 1 do
  begin
    Sec := FSections[i];
    if (Sec.Name <> '') then
      if (Sec.Name[1] = '/') then
      begin
        t := Sec.Name;
        delete(t, 1, 1);
        val(string(t), StringOfs, err);
        if err = 0 then
          if FCOFF.GetString(StringOfs, t) then
            if t <> '' then
            begin
              Sec.Name := t; // long name from COFF strings
            end;
      end;
  end;
end;

function TPEImage.Is32bit: boolean;
begin
  Result := FOptionalHeader.Magic = PE_MAGIC_PE32;
end;

function TPEImage.Is64bit: boolean;
begin
  Result := FOptionalHeader.Magic = PE_MAGIC_PE32PLUS;
end;

function TPEImage.IsDLL: boolean;
begin
  Result := (FFileHeader.Characteristics and IMAGE_FILE_DLL) <> 0;
end;

class function TPEImage.IsPE(const FileName: string): boolean;
var
  Stream: TFileStream;
begin
  Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
  try
    Result := TPEImage.IsPE(Stream);
  finally
    Stream.Free;
  end;
end;

class function TPEImage.IsPE(AStream: TStream; Ofs: UInt64): boolean;
var
  dos: TImageDOSHeader;
  pe00: uint32;
begin
  if AStream.Seek(Ofs, soFromBeginning) <> Ofs then
    exit(false);

  if (AStream.Read(dos, SizeOf(dos)) = SizeOf(dos)) then
    if (dos.e_magic = MZ_SIGNATURE) then
    begin
      Ofs := Ofs + dos.e_lfanew;
      if Ofs >= AStream.Size then
        exit(false);
      if AStream.Seek(Ofs, soFromBeginning) = Ofs then
        if AStream.Read(pe00, SizeOf(pe00)) = SizeOf(pe00) then
          if pe00 = PE00_SIGNATURE then
            exit(True);
    end;
  exit(false);
end;

function TPEImage.GetImageBits: UInt16;
begin
  case FOptionalHeader.Magic of
    PE_MAGIC_PE32:
      Result := 32;
    PE_MAGIC_PE32PLUS:
      Result := 64;
  else
    Result := 0;
  end;
end;

function TPEImage.GetImageDOSHeader: PImageDOSHeader;
begin
  Result := @self.FDosHeader;
end;

procedure TPEImage.SetImageBits(Value: UInt16);
begin
  case Value of
    32:
      FOptionalHeader.Magic := PE_MAGIC_PE32;
    64:
      FOptionalHeader.Magic := PE_MAGIC_PE32PLUS;
  else
    begin
      FOptionalHeader.Magic := 0;
      raise Exception.Create('Value unsupported.');
    end;
  end;
end;

procedure TPEImage.SetPositionRVA(const Value: TRVA);
begin
  FPositionRVA := Value;
end;

procedure TPEImage.SetPositionVA(const Value: TVA);
begin
  FPositionRVA := Value - FOptionalHeader.ImageBase;
end;

function TPEImage.FileAlignmentGet: uint32;
begin
  Result := FOptionalHeader.FileAlignment;
end;

procedure TPEImage.FileAlignmentSet(const Value: uint32);
begin
  FOptionalHeader.FileAlignment := Value;
end;

function TPEImage.SectionAlignmentGet: uint32;
begin
  Result := FOptionalHeader.SectionAlignment;
end;

procedure TPEImage.SectionAlignmentSet(const Value: uint32);
begin
  FOptionalHeader.SectionAlignment := Value;
end;

function TPEImage.SeekRVA(RVA: TRVA): boolean;
begin
  Result := RVAToOfs(RVA, nil);
  if Result then
    FPositionRVA := RVA;
end;

function TPEImage.SeekVA(VA: TVA): boolean;
begin
  Result := SeekRVA(VAToRVA(VA));
end;

function TPEImage.Read(Buffer: Pointer; Count: cardinal): uint32;
var
  Mem: Pointer;
begin
  if Count = 0 then
    exit(0);
  Mem := RVAToMem(FPositionRVA);
  if Mem <> nil then
  begin
    if Buffer <> nil then
      move(Mem^, Buffer^, Count);
    inc(FPositionRVA, Count);
    exit(Count);
  end;
  exit(0);
end;

function TPEImage.ReadEx(Buffer: Pointer; Count: cardinal): boolean;
begin
  Result := Read(Buffer, Count) = Count;
end;

procedure TPEImage.Skip(Count: integer);
begin
  inc(FPositionRVA, Count);
end;

procedure TPEImage.SourceStreamFree(Stream: TStream);
begin
  if FImageKind = PEIMAGE_KIND_DISK then
    Stream.Free;
end;

function TPEImage.SourceStreamGet(Mode: word): TStream;
begin
  if FImageKind = PEIMAGE_KIND_DISK then
    Result := TFileStream.Create(FFileName, Mode)
  else
    Result := FPEMemoryStream;
end;

function TPEImage.ReadUnicodeString: UnicodeString;
var
  Len, i: UInt16;
begin
  Len := ReadUInt16;
  SetLength(Result, Len);
  for i := 1 to Len do
    Read(@Result[i], 2);
end;

procedure TPEImage.RegionRemove(RVA: TRVA; Size: uint32);
begin
  // Currently it's just placeholder.
  // Mark memory as free.
  FSections.FillMemory(RVA, Size, $CC);
end;

function TPEImage.ReadANSIString: RawByteString;
var
  B: byte;
begin
  Result := '';
  while ReadEx(@B, 1) and (B <> 0) do
    Result := Result + AnsiChar(B);
end;

function TPEImage.ReadANSIString(out Value: RawByteString): RawByteString;
begin
  Value := ReadANSIString;
  Result := Value;
end;

function TPEImage.ReadUInt8: UInt8;
begin
  if not ReadUInt8(@Result) then
    DoReadError;
end;

function TPEImage.ReadUInt16: UInt16;
begin
  if not ReadUInt16(@Result) then
    DoReadError;
end;

function TPEImage.ReadUInt32: uint32;
begin
  if not ReadUInt32(@Result) then
    DoReadError;
end;

function TPEImage.ReadUInt64: UInt64;
begin
  if not ReadUInt64(@Result) then
    DoReadError;
end;

function TPEImage.ReadUIntPE: UInt64;
begin
  if not ReadUIntPE(@Result) then
    DoReadError;
end;

function TPEImage.ReadUInt8(OutData: PUInt8): boolean;
begin
  Result := ReadEx(OutData, 1);
end;

function TPEImage.ReadUInt16(OutData: PUInt16): boolean;
begin
  Result := ReadEx(OutData, 2);
end;

function TPEImage.ReadUInt32(OutData: PUInt32): boolean;
begin
  Result := ReadEx(OutData, 4);
end;

function TPEImage.ReadUInt64(OutData: PUInt64): boolean;
begin
  Result := ReadEx(OutData, 8);
end;

function TPEImage.ReadUIntPE(OutData: PUInt64): boolean;
begin
  if OutData <> nil then
    OutData^ := 0;

  case ImageBits of
    32:
      Result := ReadEx(OutData, 4);
    64:
      Result := ReadEx(OutData, 8);
  else
    begin
      DoReadError;
      Result := false; // compiler friendly
    end;
  end;
end;

function TPEImage.Write(Buffer: Pointer; Count: cardinal): uint32;
var
  Mem: Pointer;
begin
  Mem := RVAToMem(FPositionRVA);
  if Mem <> nil then
  begin
    if Buffer <> nil then
      move(Buffer^, Mem^, Count);
    inc(FPositionRVA, Count);
    exit(Count);
  end;
  exit(0);
end;

function TPEImage.RVAToMem(RVA: TRVA): Pointer;
var
  Ofs: integer;
  s: TPESection;
begin
  if RVAToSec(RVA, @s) and (s.Mem <> nil) then
  begin
    Ofs := RVA - s.RVA;
    exit(@s.Mem[Ofs]);
  end;
  exit(nil);
end;

function TPEImage.RVAExists(RVA: TRVA): boolean;
begin
  Result := RVAToSec(RVA, nil);
end;

function TPEImage.RVAToOfs(RVA: TRVA; OutOfs: PDword): boolean;
begin
  Result := FSections.RVAToOfs(RVA, OutOfs);
end;

function TPEImage.RVAToSec(RVA: TRVA; OutSec: PPESection): boolean;
begin
  Result := FSections.RVAToSec(RVA, OutSec);
end;

function TPEImage.RVAToVA(RVA: TRVA): UInt64;
begin
  Result := RVA + FOptionalHeader.ImageBase;
end;

function TPEImage.VAExists(VA: TRVA): boolean;
begin
  Result := RVAToSec(VA - FOptionalHeader.ImageBase, nil);
end;

function TPEImage.VAToMem(VA: TVA): Pointer;
begin
  Result := RVAToMem(VAToRVA(VA));
end;

function TPEImage.VAToOfs(VA: TVA; OutOfs: PDword): boolean;
begin
  Result := RVAToOfs(VAToRVA(VA), OutOfs);
end;

function TPEImage.VAToSec(VA: TRVA; OutSec: PPESection): boolean;
begin
  Result := RVAToSec(VAToRVA(VA), OutSec);
end;

function TPEImage.VAToRVA(VA: TVA): TRVA;
begin
  Result := VA - FOptionalHeader.ImageBase;
end;

function TPEImage.LoadFromFile(const AFileName: string;
  AParseStages: TParserFlags): boolean;
var
  fs: TFileStream;
begin
  if not FileExists(AFileName) then
  begin
    FMsg.Write('File not found.');
    exit(false);
  end;

  fs := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    FFileName := AFileName;
    fs.Position := 0;
    Result := LoadFromStream(fs, AParseStages);
  finally
    fs.Free;
  end;
end;

function TPEImage.LoadFromMappedImage(const AFileName: string;
  AParseStages: TParserFlags): boolean;
begin
  FPEMemoryStream := TPEMemoryStream.Create(AFileName);
  Result := LoadFromStream(FPEMemoryStream, AParseStages, PEIMAGE_KIND_MEMORY);
end;

function TPEImage.LoadFromStream(AStream: TStream; AParseStages: TParserFlags;
  ImageKind: TPEImageKind): boolean;
var
  OptHdrOfs, SecHdrOfs, SecHdrEndOfs, SecDataOfs: TFileOffset;
  SecHdrGapSize: integer;
  OptHdrSizeRead: int32; // w/o directories
  Stage: TParserFlag;
  Parser: TPEParser;
  Signature: uint32;
  DOSBlockSize: uint32;
begin
  Result := false;

  FImageKind := ImageKind;
  FFileSize := AStream.Size;

  // DOS header.
  if not LoadDosHeader(AStream, FDosHeader) then
    exit; // dos header failed

  if (FDosHeader.e_lfanew mod 8) <> 0 then
  begin
    Msg.Write('PE header is not 8-byte aligned.');
    exit;
  end;

  // Check if e_lfanew is ok
  if not StreamSeek(AStream, FDosHeader.e_lfanew) then
    exit; // e_lfanew is wrong

  // @ e_lfanew

  // Store offset of NT headers.
  FLFANew := FDosHeader.e_lfanew;

  // Read DOS Block
  DOSBlockSize := FDosHeader.e_lfanew - SizeOf(FDosHeader);
  SetLength(self.FDosBlock, DOSBlockSize);
  if (DOSBlockSize <> 0) then
    if StreamSeek(AStream, SizeOf(FDosHeader)) then
    begin
      if not StreamRead(AStream, self.FDosBlock[0], DOSBlockSize) then
        SetLength(self.FDosBlock, 0);
    end;

  // Go back to new header.
  if not StreamSeek(AStream, FDosHeader.e_lfanew) then
    exit; // e_lfanew is wrong

  // Load signature.
  if not StreamRead(AStream, Signature, SizeOf(Signature)) then
    exit;
  // Check signature.
  if Signature <> PE00_SIGNATURE then
    exit; // not PE file

  // Load File Header.
  if not LoadFileHeader(AStream, FFileHeader) then
    exit; // File Header failed.

  // Get offsets of Optional Header and Section Headers.
  OptHdrOfs := AStream.Position;
  SecHdrOfs := OptHdrOfs + FFileHeader.SizeOfOptionalHeader;
  SecHdrEndOfs := SecHdrOfs + SizeOf(TImageSectionHeader) *
    FFileHeader.NumberOfSections;

  // Read COFF.
  FCOFF.LoadFromStream(AStream);

  // Load Section Headers first.
  AStream.Position := SecHdrOfs;
  LoadSectionHeaders(AStream);

  // Mapped image can't have overlay, so correct total size.
  if FImageKind = PEIMAGE_KIND_MEMORY then
    FFileSize := CalcRawSizeOfImage;

  // Convert /%num% section names to long names if possible.
  ResolveSectionNames;

  // Read Gap after Section Header.
  if FSections.Count <> 0 then
  begin
    SecDataOfs := FSections.First.RawOffset;
    if SecDataOfs >= SecHdrEndOfs then
    begin
      SecHdrGapSize := SecDataOfs - SecHdrEndOfs;
      SetLength(self.FSecHdrGap, SecHdrGapSize);
      if SecHdrGapSize <> 0 then
      begin
        AStream.Position := SecHdrEndOfs;
        AStream.Read(self.FSecHdrGap[0], SecHdrGapSize);
      end;
    end;
  end;

  // Read opt.hdr. magic to know if image is 32 or 64 bit.
  AStream.Position := OptHdrOfs;
  if not StreamPeek(AStream, FOptionalHeader.Magic,
    SizeOf(FOptionalHeader.Magic)) then
    exit;

  // Safe read optional header.
  OptHdrSizeRead := FOptionalHeader.ReadFromStream(AStream, ImageBits, -1);

  if OptHdrSizeRead <> 0 then
  begin
    // Read data directories from current pos top SecHdrOfs.
    FDataDirectories.LoadFromStream(AStream, Msg, AStream.Position, SecHdrOfs,
      FOptionalHeader.NumberOfRvaAndSizes);
  end;

  Result := True;

  // Load section data.
  LoadSectionData(AStream);

  // Execute parsers.
  if AParseStages <> [] then
  begin
    for Stage in AParseStages do
      if Assigned(FParsers[Stage]) then
      begin
        Parser := FParsers[Stage].Create(self);
        try
          case Parser.Parse of
            PR_ERROR:
              Msg.Write('[%s] Parser returned error.', [Parser.ToString]);
            PR_SUSPICIOUS:
              Msg.Write('[%s] Parser returned status SUSPICIOUS.',
                [Parser.ToString]);
          end;
        finally
          Parser.Free;
        end;
      end;
  end;
end;

function TPEImage.SaveToStream(AStream: TStream): boolean;
begin
  Result := PE.Image.Saving.SaveImageToStream(self, AStream);
end;

function TPEImage.SaveToFile(const AFileName: string): boolean;
var
  fs: TFileStream;
begin
  fs := TFileStream.Create(AFileName, fmCreate);
  try
    Result := SaveToStream(fs);
  finally
    fs.Free;
  end;
end;

function TPEImage.GetOptionalHeader: PPEOptionalHeader;
begin
  Result := @self.FOptionalHeader;
end;

function TPEImage.GetOverlay: POverlay;
var
  lastSec: TPESection;
begin
  lastSec := GetLastSectionWithValidRawData;

  if (lastSec <> nil) then
  begin
    FOverlay.Offset := lastSec.GetEndRawOffset; // overlay offset

    // Check overlay offet present in file.
    if FOverlay.Offset < FFileSize then
    begin
      FOverlay.Size := FFileSize - FOverlay.Offset;
      exit(@FOverlay);
    end;
  end;

  exit(nil);
end;

function TPEImage.GetPositionVA: TVA;
begin
  Result := FPositionRVA + FOptionalHeader.ImageBase;
end;

function TPEImage.GetLastSectionWithValidRawData: TPESection;
var
  i: integer;
begin
  for i := FSections.Count - 1 downto 0 do
    if (FSections[i].RawOffset <> 0) and (FSections[i].RawSize <> 0) then
      exit(FSections[i]);
  exit(nil);
end;

function TPEImage.SaveOverlayToFile(const AFileName: string;
  Append: boolean = false): boolean;
var
  src, dst: TStream;
  ovr: POverlay;
begin
  Result := false;

  ovr := GetOverlay;
  if Assigned(ovr) then
  begin
    // If no overlay, we're done.
    if ovr^.Size = 0 then
      exit(True);
    try
      src := SourceStreamGet(fmOpenRead or fmShareDenyWrite);

      if Append and FileExists(AFileName) then
      begin
        dst := TFileStream.Create(AFileName, fmOpenReadWrite or fmShareDenyWrite);
        dst.Seek(0, soFromEnd);
      end
      else
        dst := TFileStream.Create(AFileName, fmCreate);

      try
        src.Seek(ovr^.Offset, soFromBeginning);
        dst.CopyFrom(src, ovr^.Size);
        Result := True;
      finally
        SourceStreamFree(src);
        dst.Free;
      end;
    except
    end;
  end;
end;

function TPEImage.RemoveOverlay: boolean;
var
  ovr: POverlay;
  fs: TFileStream;
begin
  Result := false;

  if FImageKind = PEIMAGE_KIND_MEMORY then
  begin
    FMsg.Write('Can''t remove overlay from mapped image.');
    exit;
  end;

  ovr := GetOverlay;
  if (ovr <> nil) and (ovr^.Size <> 0) then
  begin
    try
      fs := TFileStream.Create(FFileName, fmOpenWrite or fmShareDenyWrite);
      try
        fs.Size := fs.Size - ovr^.Size; // Trim file.
        self.FFileSize := fs.Size;      // Update filesize.
        Result := True;
      finally
        fs.Free;
      end;
    except
    end;
  end;
end;

function TPEImage.LoadOverlayFromFile(const AFileName: string; Offset,
  Size: UInt64): boolean;
var
  ovr: POverlay;
  fs: TFileStream;
  src: TStream;
  newImgSize: uint32;
begin
  Result := false;

  if FImageKind = PEIMAGE_KIND_MEMORY then
  begin
    FMsg.Write('Can''t append overlay to mapped image.');
    exit;
  end;

  fs := TFileStream.Create(FFileName, fmOpenWrite or fmShareDenyWrite);
  src := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyWrite);
  try
    if (Offset = 0) and (Size = 0) then
      Size := src.Size;
    if Size <> 0 then
    begin
      if (Offset + Size) > src.Size then
        exit(False);
      src.Position := Offset;

      ovr := GetOverlay;
      if (ovr <> nil) and (ovr^.Size <> 0) then
        fs.Size := fs.Size - ovr^.Size // Trim file.
      else
      begin
        newImgSize := CalcRawSizeOfImage();
        fs.Size := newImgSize;
      end;

      fs.Position := fs.Size;

      fs.CopyFrom(src, Size);

      self.FFileSize := fs.Size; // Update filesize.
    end;
    Result := True;
  finally
    src.Free;
    fs.Free;
  end;
end;

end.

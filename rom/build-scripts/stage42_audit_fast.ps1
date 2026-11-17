$ErrorActionPreference = 'Stop'

$Base = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage41_FANPERF_LABELS\images\super.img'
$Candidate = 'D:\K90Max_ColorOS17_完整迁移_20261028\01_主工程\K90_A17_PORT_WORK\delivery\K90Max_ColorOS17_Prague_KEEPDATA_Native_Stage42_FANPERF_POLICY\images\super.img'
$OdmStart = [int64]2615552 * 4096
$OdmLength = [int64]421028 * 4096
$OdmEnd = $OdmStart + $OdmLength
$ExpectedSize = [int64]13421772800

Add-Type -TypeDefinition @'
using System;
using System.IO;

public static class BinaryRangeAudit {
    public static void Compare(string left, string right, long offset, long length) {
        const int BufferSize = 16 * 1024 * 1024;
        byte[] a = new byte[BufferSize];
        byte[] b = new byte[BufferSize];
        using (var fa = new FileStream(left, FileMode.Open, FileAccess.Read, FileShare.Read, BufferSize, FileOptions.SequentialScan))
        using (var fb = new FileStream(right, FileMode.Open, FileAccess.Read, FileShare.Read, BufferSize, FileOptions.SequentialScan)) {
            fa.Position = offset;
            fb.Position = offset;
            long compared = 0;
            while (compared < length) {
                int want = (int)Math.Min(BufferSize, length - compared);
                int ra = ReadFull(fa, a, want);
                int rb = ReadFull(fb, b, want);
                if (ra != want || rb != want) throw new EndOfStreamException();
                for (int i = 0; i < want; i++) {
                    if (a[i] != b[i]) {
                        throw new InvalidDataException("Difference at absolute offset " + (offset + compared + i));
                    }
                }
                compared += want;
            }
        }
    }

    private static int ReadFull(Stream stream, byte[] buffer, int count) {
        int total = 0;
        while (total < count) {
            int n = stream.Read(buffer, total, count - total);
            if (n == 0) break;
            total += n;
        }
        return total;
    }
}
'@

$BaseInfo = Get-Item -LiteralPath $Base
$CandidateInfo = Get-Item -LiteralPath $Candidate
if ($BaseInfo.Length -ne $ExpectedSize -or $CandidateInfo.Length -ne $ExpectedSize) {
    throw 'super.img size mismatch'
}

[BinaryRangeAudit]::Compare($Base, $Candidate, 0, $OdmStart)
[BinaryRangeAudit]::Compare($Base, $Candidate, $OdmEnd, $ExpectedSize - $OdmEnd)

"OUTSIDE_ODM_BYTE_IDENTICAL"
"ODM_START=$OdmStart"
"ODM_LENGTH=$OdmLength"
"ODM_END=$OdmEnd"

# Kokoro's espeakng-loader ships an x86_64 Linux wheel only, and the frame
# capture is only ever exercised here. Widen this when either changes.
{
  systems = [ "x86_64-linux" ];
}

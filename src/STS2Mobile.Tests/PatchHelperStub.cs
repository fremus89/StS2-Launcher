// Minimal stand-in for STS2Mobile.PatchHelper so linked sources that call
// PatchHelper.Log(...) compile in the test project without pulling in the
// real HarmonyLib / Godot / sts2 references. Tests do not assert on log
// output; this just satisfies the symbol.
namespace STS2Mobile
{
    internal static class PatchHelper
    {
        public static void Log(string msg) { }
    }
}

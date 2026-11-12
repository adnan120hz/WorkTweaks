// MARK: - PosterBoard wallpaper-maker template
//
// Byte-exact template files for the descriptor the maker builds.
// The Floating layer is Pocket Poster's blank 3176x3176 layer
// (GPL-3.0, leminlimez/Pocket-Poster — see License & Credits);
// providerInfo.plist is the same file's NSKeyedArchiver blob.
// The Background layer is generated per wallpaper (frames +
// main.caml + index.xml), so it is not stored here.

enum PosterBoardTemplate {
    /// Blank Floating layer (3176x3176, no contents).
    static let floatingMainCaml = #"""
<?xml version="1.0" encoding="UTF-8"?>

<caml xmlns="http://www.apple.com/CoreAnimation/1.0">
  <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" bounds="0 0 3176 3176" contentsFormat="RGBA8" cornerCurve="circular" hidden="0" name="_BACKGROUND" position="1588 1588">
    <sublayers>
      <CALayer allowsEdgeAntialiasing="1" allowsGroupOpacity="1" anchorPoint="0 0" bounds="0 0 0 0" contentsFormat="RGBA8" cornerCurve="circular" name="_CENTER_BACKGROUND" position="1588 1588"/>
    </sublayers>
    <states>
      <LKState name="Locked">
	<elements/>
      </LKState>
      <LKState name="Unlock">
	<elements/>
      </LKState>
      <LKState name="Sleep">
	<elements/>
      </LKState>
    </states>
    <stateTransitions>
      <LKStateTransition fromState="*" toState="Unlock">
	<elements/>
      </LKStateTransition>
      <LKStateTransition fromState="Unlock" toState="*">
	<elements/>
      </LKStateTransition>
      <LKStateTransition fromState="*" toState="Locked">
	<elements/>
      </LKStateTransition>
      <LKStateTransition fromState="Locked" toState="*">
	<elements/>
      </LKStateTransition>
      <LKStateTransition fromState="*" toState="Sleep">
	<elements/>
      </LKStateTransition>
      <LKStateTransition fromState="Sleep" toState="*">
	<elements/>
      </LKStateTransition>
    </stateTransitions>
  </CALayer>
</caml>
"""#

    /// Floating layer index (document 3176x3176, root main.caml).
    static let floatingIndexXml = #"""
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>assetManifest</key>
	<string>assetManifest.caml</string>
	<key>documentHeight</key>
	<real>3176</real>
	<key>documentResizesToView</key>
	<false/>
	<key>documentWidth</key>
	<real>3176</real>
	<key>dynamicGuidesEnabled</key>
	<true/>
	<key>geometryFlipped</key>
	<false/>
	<key>guidesEnabled</key>
	<true/>
	<key>interactiveMouseEventsEnabled</key>
	<true/>
	<key>interactiveShowsCursor</key>
	<true/>
	<key>interactiveTouchEventsEnabled</key>
	<false/>
	<key>loopEnd</key>
	<real>0.0</real>
	<key>loopStart</key>
	<real>0.0</real>
	<key>loopingEnabled</key>
	<false/>
	<key>multitouchDisablesMouse</key>
	<false/>
	<key>multitouchEnabled</key>
	<false/>
	<key>presentationMouseEventsEnabled</key>
	<true/>
	<key>presentationShowsCursor</key>
	<true/>
	<key>presentationTouchEventsEnabled</key>
	<false/>
	<key>rootDocument</key>
	<string>main.caml</string>
	<key>savesWindowFrame</key>
	<false/>
	<key>scalesToFitInPlayer</key>
	<false/>
	<key>showsTouches</key>
	<true/>
	<key>snappingEnabled</key>
	<true/>
	<key>timelineMarkers</key>
	<string>[(null)]</string>
	<key>touchesColor</key>
	<string>1 1 0 0.8</string>
	<key>unitsInPixelsInPlayer</key>
	<true/>
</dict>
</plist>
"""#

    /// providerInfo.plist (NSKeyedArchiver, kConfigurationLastUseDateKey)
    /// as base64, byte-identical to Pocket Poster's template file.
    static let providerInfoBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGmCwwVFhogVSRudWxs0w0ODxASFFdOUy5rZXlzWk5TLm9iamVjdHNWJGNsYXNzoRGAAqETgAOABV8QHGtDb25maWd1cmF0aW9uTGFzdFVzZURhdGVLZXnSFw8YGVdOUy50aW1lI0HGwARI1HUUgATSGxwdHlokY2xhc3NuYW1lWCRjbGFzc2VzVk5TRGF0ZaIdH1hOU09iamVjdNIbHCEiXxATTlNNdXRhYmxlRGljdGlvbmFyeaMjJB9fEBNOU011dGFibGVEaWN0aW9uYXJ5XE5TRGljdGlvbmFyeQAIABEAGgAkACkAMgA3AEkATABRAFMAWgBgAGcAbwB6AIEAgwCFAIcAiQCLAKoArwC3AMAAwgDHANIA2wDiAOUA7gDzAQkBDQEjAAAAAAAAAgEAAAAAAAAAJQAAAAAAAAAAAAAAAAAAATA="

    /// assetManifest.caml — Apple's trivial MicaAssetManifest,
    /// present in every .ca folder of Apple's own wallpapers.
    static let assetManifestCaml = """
<?xml version="1.0" encoding="UTF-8"?>

<caml xmlns="http://www.apple.com/CoreAnimation/1.0">
  <MicaAssetManifest>
    <modules type="NSArray"/>
  </MicaAssetManifest>
</caml>
"""
}

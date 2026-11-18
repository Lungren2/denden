import { loadFont } from "@remotion/fonts";
import { staticFile } from "remotion";

// Den Den's dark palette (/usr/share/denden/noctalia/DenDen.json).
export const c = {
  bg: "#000000",
  surface: "#111111",
  outline: "#1c1c1c",
  text: "#f5f5f5",
  muted: "#a3a3a3",
  dim: "#737373",
  primary: "#346bf1",
  tertiary: "#8fb0ff",
  green: "#00d492",
  yellow: "#ffb900",
  red: "#ff6467",
  snail: "#eceef2",
};

export const font = "Inter";
export const mono = "'Cascadia Mono', monospace";

loadFont({ family: font, url: staticFile("InterVariable.ttf"), weight: "100 900" });
loadFont({ family: "Cascadia Mono", url: staticFile("CascadiaMono.ttf"), weight: "200 700" });

export const glass: React.CSSProperties = {
  background: "rgba(17,17,17,0.72)",
  border: "1px solid rgba(255,255,255,0.08)",
  borderRadius: 20,
  boxShadow: "0 30px 80px rgba(0,0,0,0.6)",
  backdropFilter: "blur(24px)",
};

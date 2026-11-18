import {
  AbsoluteFill,
  Easing,
  interpolate,
  Sequence,
  spring,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Mushi } from "./Mushi";
import { c, font, glass, mono } from "./theme";

const clamp = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ease = Easing.bezier(0.22, 1, 0.36, 1);

/** Fades a scene in over its first frames and out over its last. */
const Scene: React.FC<{ len: number; children: React.ReactNode }> = ({ len, children }) => {
  const f = useCurrentFrame();
  const o = interpolate(f, [0, 12, len - 12, len], [0, 1, 1, 0], clamp);
  return <AbsoluteFill style={{ opacity: o }}>{children}</AbsoluteFill>;
};

const useSpring = (delay = 0, damping = 14) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - delay, fps, config: { damping, mass: 0.8 } });
};

/** A soft blue glow behind everything, drifting slowly. */
const Backdrop: React.FC = () => {
  const f = useCurrentFrame();
  const x = 50 + Math.sin(f / 90) * 8;
  const y = 45 + Math.cos(f / 110) * 6;
  return (
    <AbsoluteFill
      style={{
        background: `radial-gradient(60% 60% at ${x}% ${y}%, rgba(52,107,241,0.20), rgba(0,0,0,0) 70%), ${c.bg}`,
      }}
    />
  );
};

// ─── 1. The snail arrives ────────────────────────────────────────────────

const Intro: React.FC = () => {
  const f = useCurrentFrame();
  const pop = useSpring(4, 11);
  // den den, den den: two short rings once it has landed
  const ring = interpolate(f, [26, 30, 40, 44, 50, 54, 64, 68], [0, 1, 1, 0, 0, 1, 1, 0], clamp);
  const title = useSpring(34, 16);
  return (
    <Scene len={110}>
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 24 }}>
        <div style={{ transform: `scale(${pop}) translateY(${(1 - pop) * 40}px)` }}>
          <Mushi size={300} ring={ring} frame={f} />
        </div>
        <div
          style={{
            fontFamily: font,
            fontWeight: 700,
            fontSize: 132,
            letterSpacing: -5,
            color: c.text,
            opacity: title,
            transform: `translateY(${(1 - title) * 30}px)`,
          }}
        >
          Den Den
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

// ─── 2. The pitch ────────────────────────────────────────────────────────

const Words: React.FC<{ text: string; start?: number; stagger?: number; style?: React.CSSProperties }> = ({
  text,
  start = 0,
  stagger = 4,
  style,
}) => {
  const f = useCurrentFrame();
  return (
    <span style={style}>
      {text.split(" ").map((w, i) => {
        const p = interpolate(f, [start + i * stagger, start + i * stagger + 14], [0, 1], { ...clamp, easing: ease });
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              marginRight: "0.26em",
              opacity: p,
              transform: `translateY(${(1 - p) * 24}px)`,
              filter: `blur(${(1 - p) * 6}px)`,
            }}
          >
            {w}
          </span>
        );
      })}
    </span>
  );
};

const Pitch: React.FC = () => (
  <Scene len={100}>
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 28 }}>
      <Words
        text="A computer you run"
        style={{ fontFamily: font, fontWeight: 700, fontSize: 104, letterSpacing: -3.5, color: c.text }}
      />
      <Words
        text="by talking to it."
        start={22}
        style={{ fontFamily: font, fontWeight: 700, fontSize: 104, letterSpacing: -3.5, color: c.tertiary }}
      />
    </AbsoluteFill>
  </Scene>
);

// ─── 3. Ask, and it changes ──────────────────────────────────────────────

const ASK = "Make the taskbar smaller and put the clock on the left.";

const Taskbar: React.FC<{ shrink: number }> = ({ shrink }) => {
  const h = interpolate(shrink, [0, 1], [76, 50]);
  const icon = interpolate(shrink, [0, 1], [44, 30]);
  const clockLeft = interpolate(shrink, [0, 1], [1700, 24]);
  const clock = (
    <div style={{ fontFamily: font, fontSize: interpolate(shrink, [0, 1], [22, 17]), color: c.text, fontWeight: 500 }}>
      13:49 <span style={{ color: c.muted, fontWeight: 400 }}>Wed 18 Nov</span>
    </div>
  );
  return (
    <div
      style={{
        position: "absolute",
        left: 16,
        right: 16,
        bottom: 16,
        height: h,
        ...glass,
        borderRadius: 16,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        gap: 14,
      }}
    >
      <div style={{ width: icon, height: icon, opacity: 0.95 }}>
        <Mushi size={icon} />
      </div>
      {[c.text, c.primary, "#2d333f", c.green].map((col, i) => (
        <div
          key={i}
          style={{
            width: icon,
            height: icon,
            borderRadius: icon * 0.28,
            background: i === 0 ? "#fff" : col,
            color: "#000",
            fontFamily: font,
            fontWeight: 800,
            fontSize: icon * 0.42,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {i === 0 ? "T3" : ""}
        </div>
      ))}
      <div style={{ position: "absolute", left: clockLeft, top: 0, bottom: 0, display: "flex", alignItems: "center" }}>
        {clock}
      </div>
    </div>
  );
};

const DiffLine: React.FC<{ sign: "-" | "+"; text: string; p: number }> = ({ sign, text, p }) => (
  <div
    style={{
      fontFamily: mono,
      fontSize: 24,
      padding: "6px 18px",
      color: sign === "+" ? c.green : c.red,
      background: sign === "+" ? "rgba(0,212,146,0.10)" : "rgba(255,100,103,0.10)",
      opacity: p,
      transform: `translateX(${(1 - p) * -20}px)`,
    }}
  >
    {sign} {text}
  </div>
);

const Ask: React.FC = () => {
  const f = useCurrentFrame();
  const win = useSpring(6, 16);
  const typed = Math.round(interpolate(f, [24, 92], [0, ASK.length], clamp));
  const sent = interpolate(f, [98, 108], [0, 1], clamp);
  const thinking = f > 108 && f < 138;
  const card = useSpring(136, 16);
  const line = (i: number) => interpolate(f, [150 + i * 8, 162 + i * 8], [0, 1], clamp);
  const shrink = interpolate(f, [196, 230], [0, 1], { ...clamp, easing: ease });
  const done = interpolate(f, [232, 248], [0, 1], clamp);

  return (
    <Scene len={300}>
      <AbsoluteFill
        style={{
          background: `radial-gradient(80% 70% at 70% 20%, rgba(52,107,241,0.35), rgba(0,0,0,0) 70%),
                       radial-gradient(60% 60% at 10% 90%, rgba(143,176,255,0.18), rgba(0,0,0,0) 70%), #050608`,
        }}
      />
      {/* the chat */}
      <div
        style={{
          position: "absolute",
          left: 360,
          top: 150,
          width: 1200,
          height: 640,
          ...glass,
          opacity: win,
          transform: `translateY(${(1 - win) * 60}px) scale(${0.96 + win * 0.04})`,
          padding: 48,
          display: "flex",
          flexDirection: "column",
          gap: 26,
          fontFamily: font,
        }}
      >
        <div style={{ color: c.muted, fontSize: 20, display: "flex", gap: 10, alignItems: "center" }}>
          <span style={{ color: c.text, fontWeight: 700 }}>T3 Code</span> · Den Den
        </div>

        {/* user message */}
        <div
          style={{
            alignSelf: "flex-end",
            maxWidth: 760,
            background: sent > 0 ? "#1c1c1c" : "transparent",
            border: `1px solid ${sent > 0 ? "transparent" : "rgba(255,255,255,0.12)"}`,
            borderRadius: 18,
            padding: "18px 24px",
            fontSize: 30,
            color: c.text,
            lineHeight: 1.35,
            transform: `translateY(${(1 - sent) * 0}px)`,
          }}
        >
          {ASK.slice(0, typed)}
          {sent === 0 && f % 30 < 18 ? <span style={{ color: c.tertiary }}>▍</span> : null}
        </div>

        {thinking && (
          <div style={{ display: "flex", gap: 10, paddingLeft: 6 }}>
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                style={{
                  width: 12,
                  height: 12,
                  borderRadius: 6,
                  background: c.muted,
                  opacity: 0.3 + 0.7 * Math.max(0, Math.sin((f - i * 5) / 4)),
                }}
              />
            ))}
          </div>
        )}

        {/* the edit */}
        {f >= 136 && (
          <div
            style={{
              borderRadius: 14,
              border: "1px solid rgba(255,255,255,0.08)",
              background: "#0b0b0b",
              overflow: "hidden",
              opacity: card,
              transform: `translateY(${(1 - card) * 20}px)`,
              width: 780,
            }}
          >
            <div style={{ padding: "14px 18px", fontSize: 21, color: c.muted, borderBottom: "1px solid #1c1c1c" }}>
              Edited <span style={{ color: c.text, fontFamily: mono }}>~/.config/noctalia/config.toml</span>
            </div>
            <div style={{ padding: "10px 0" }}>
              <DiffLine sign="-" text="bar.height = 76" p={line(0)} />
              <DiffLine sign="+" text="bar.height = 50" p={line(1)} />
              <DiffLine sign="-" text='bar.clock  = "right"' p={line(2)} />
              <DiffLine sign="+" text='bar.clock  = "left"' p={line(3)} />
            </div>
          </div>
        )}

        <div
          style={{
            fontSize: 30,
            color: c.text,
            opacity: done,
            transform: `translateY(${(1 - done) * 14}px)`,
          }}
        >
          Done. It reloads live, nothing to restart.
        </div>
      </div>
      <Taskbar shrink={shrink} />
    </Scene>
  );
};

// ─── 4. Three beats ──────────────────────────────────────────────────────

const Headline: React.FC<{ top: string; bottom: string }> = ({ top, bottom }) => (
  <div style={{ textAlign: "center", fontFamily: font, fontWeight: 700, fontSize: 78, letterSpacing: -2.5, lineHeight: 1.08 }}>
    <Words text={top} style={{ color: c.text }} />
    <br />
    <Words text={bottom} start={10} style={{ color: c.dim }} />
  </div>
);

const Beat: React.FC<{ top: string; bottom: string; children: React.ReactNode }> = ({ top, bottom, children }) => (
  <Scene len={110}>
    <Backdrop />
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", gap: 70, flexDirection: "column" }}>
      <Headline top={top} bottom={bottom} />
      {children}
    </AbsoluteFill>
  </Scene>
);

const Snapshots: React.FC = () => {
  const f = useCurrentFrame();
  const marks = [
    { n: "#211", l: "hourly · /home", col: c.muted },
    { n: "#212", l: "pre · pacman -Syu", col: c.tertiary },
    { n: "#213", l: "post · pacman -Syu", col: c.tertiary },
    { n: "#214", l: "hourly · /src", col: c.muted },
  ];
  const lineW = interpolate(f, [16, 50], [0, 1], { ...clamp, easing: ease });
  const back = interpolate(f, [72, 86], [0, 1], { ...clamp, easing: ease });
  return (
    <Beat top="Every change is a snapshot." bottom="Boot any of them.">
      <div style={{ position: "relative", width: 1300, height: 160 }}>
        <div
          style={{
            position: "absolute",
            top: 40,
            left: 0,
            height: 4,
            width: 1300 * lineW,
            borderRadius: 2,
            background: `linear-gradient(90deg, rgba(143,176,255,0), ${c.tertiary})`,
          }}
        />
        {marks.map((m, i) => {
          const p = interpolate(f, [24 + i * 9, 36 + i * 9], [0, 1], { ...clamp, easing: ease });
          const picked = i === 1 ? back : 0;
          return (
            <div
              key={m.n}
              style={{
                position: "absolute",
                left: 60 + i * 320,
                top: 0,
                width: 220,
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: 22,
                opacity: p,
                transform: `scale(${0.6 + p * 0.4})`,
              }}
            >
              <div
                style={{
                  marginTop: 26,
                  width: 32,
                  height: 32,
                  borderRadius: 16,
                  background: m.col,
                  boxShadow: `0 0 ${12 + picked * 40}px ${m.col}`,
                  transform: `scale(${1 + picked * 0.4})`,
                }}
              />
              <div style={{ fontFamily: mono, fontSize: 24, color: c.text }}>{m.n}</div>
              <div style={{ fontFamily: font, fontSize: 22, color: c.muted, whiteSpace: "nowrap" }}>{m.l}</div>
            </div>
          );
        })}
      </div>
    </Beat>
  );
};

const Term: React.FC<{ lines: { t: string; col?: string; at: number }[] }> = ({ lines }) => {
  const f = useCurrentFrame();
  const win = useSpring(8, 16);
  return (
    <div
      style={{
        width: 1100,
        ...glass,
        padding: "34px 44px",
        fontFamily: mono,
        fontSize: 30,
        lineHeight: 1.7,
        opacity: win,
        transform: `translateY(${(1 - win) * 40}px)`,
      }}
    >
      {lines.map((l, i) => {
        if (f < l.at) return null;
        const isCmd = l.t.startsWith("$ ");
        const text = isCmd ? l.t.slice(0, 2 + Math.round((f - l.at) * 1.6)) : l.t;
        const o = isCmd ? 1 : interpolate(f, [l.at, l.at + 6], [0, 1], clamp);
        return (
          <div key={i} style={{ color: l.col ?? (isCmd ? c.text : c.muted), opacity: o, whiteSpace: "pre" }}>
            {isCmd ? (
              <>
                <span style={{ color: c.tertiary }}>❯</span>
                {text.slice(1)}
              </>
            ) : (
              text
            )}
          </div>
        );
      })}
    </div>
  );
};

const Source: React.FC = () => (
  <Beat top="Every program, from source." bottom="Yours stays through updates.">
    <Term
      lines={[
        { t: "$ den src get niri", at: 20 },
        { t: "  → /src/niri   git · upstream + main", at: 38 },
        { t: "$ git commit -am 'snappier animations'", at: 46 },
        { t: "$ den src build niri", at: 70 },
        { t: "  ✓ niri installed from [denden-local]", col: c.green, at: 86 },
      ]}
    />
  </Beat>
);

const Doctor: React.FC = () => (
  <Beat top="It knows itself." bottom="And so do your agents.">
    <Term
      lines={[
        { t: "$ den doctor", at: 18 },
        { t: "✓ disks       412 GB free · SMART ok", col: c.green, at: 34 },
        { t: "✓ services    none failed", col: c.green, at: 42 },
        { t: "✓ backups     6 hours ago, on the stick", col: c.green, at: 50 },
        { t: "✓ snapshots   hourly · around every update", col: c.green, at: 58 },
        { t: "! updates     3 packages ready", col: c.yellow, at: 66 },
      ]}
    />
  </Beat>
);

// ─── 5. Outro ────────────────────────────────────────────────────────────

const Outro: React.FC = () => {
  const f = useCurrentFrame();
  const pop = useSpring(2, 12);
  const ring = interpolate(f, [84, 88, 100, 104], [0, 0.8, 0.8, 0], clamp);
  const sub = interpolate(f, [30, 46], [0, 1], { ...clamp, easing: ease });
  const tags = ["Arch", "CachyOS", "niri", "T3 Code", "Claude Code", "Codex"];
  return (
    <Scene len={150}>
      <Backdrop />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", flexDirection: "column", gap: 30 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 40, transform: `scale(${0.9 + pop * 0.1})`, opacity: pop }}>
          <Mushi size={220} ring={ring} frame={f} />
          <div style={{ fontFamily: font, fontWeight: 700, fontSize: 150, letterSpacing: -6, color: c.text }}>Den Den</div>
        </div>
        <div style={{ display: "flex", gap: 14, opacity: sub, transform: `translateY(${(1 - sub) * 16}px)` }}>
          {tags.map((t, i) => (
            <div
              key={t}
              style={{
                fontFamily: font,
                fontSize: 24,
                color: c.muted,
                padding: "10px 20px",
                borderRadius: 999,
                border: "1px solid rgba(255,255,255,0.1)",
                opacity: interpolate(f, [34 + i * 4, 46 + i * 4], [0, 1], clamp),
              }}
            >
              {t}
            </div>
          ))}
        </div>
        <div
          style={{
            marginTop: 30,
            fontFamily: mono,
            fontSize: 28,
            color: c.tertiary,
            opacity: interpolate(f, [62, 78], [0, 1], clamp),
          }}
        >
          github.com/Lungren2/denden
        </div>
      </AbsoluteFill>
    </Scene>
  );
};

// ─── Timeline ────────────────────────────────────────────────────────────

export const scenes = [
  { C: Intro, len: 110 },
  { C: Pitch, len: 100 },
  { C: Ask, len: 300 },
  { C: Snapshots, len: 110 },
  { C: Source, len: 110 },
  { C: Doctor, len: 110 },
  { C: Outro, len: 150 },
];

export const totalFrames = scenes.reduce((n, s) => n + s.len, 0);

export const Launch: React.FC = () => {
  let at = 0;
  return (
    <AbsoluteFill style={{ background: c.bg }}>
      {scenes.map(({ C, len }, i) => {
        const from = at;
        at += len;
        return (
          <Sequence key={i} from={from} durationInFrames={len}>
            <C />
          </Sequence>
        );
      })}
    </AbsoluteFill>
  );
};

import { Img, staticFile } from "remotion";

// The Den Den mark, drawn by packages/denden-boot/mushi.py (`npm run mark`).
// `ring` 0..1 shakes it like a ringing phone; small sizes use the simpler
// --small drawing, as the taskbar does.
export const Mushi: React.FC<{ size: number; ring?: number; frame?: number }> = ({ size, ring = 0, frame = 0 }) => {
  const shake = ring * Math.sin(frame * 2.2) * 6;
  return (
    <Img
      src={staticFile(size <= 48 ? "mushi-small.svg" : "mushi.svg")}
      style={{
        width: size,
        height: size,
        display: "block",
        transformOrigin: "50% 84%",
        transform: `rotate(${shake}deg) translateY(${-Math.abs(shake) * 0.6}px)`,
      }}
    />
  );
};

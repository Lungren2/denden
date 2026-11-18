import { c } from "./theme";

// The Den Den mark (packages/denden-boot/src/mushi.svg). `blink` 0..1 closes
// the eyes, `cord` 0..1 draws the coiled cord.
export const Mushi: React.FC<{
  size: number;
  blink?: number;
  cord?: number;
  color?: string;
}> = ({ size, blink = 0, cord = 1, color = c.snail }) => {
  const eye = 1 - blink * 0.9;
  return (
    <svg viewBox="0 0 1024 1024" width={size} height={size}>
      <defs>
        <mask id="cut">
          <rect width="1024" height="1024" fill="white" />
          <circle cx="570" cy="530" r="108" fill="none" stroke="black" strokeWidth="16" />
          {Array.from({ length: 10 }, (_, i) => {
            const a = (-60 + i * 30) * (Math.PI / 180);
            return <circle key={i} cx={570 + 68 * Math.cos(a)} cy={530 + 68 * Math.sin(a)} r="15" fill="black" />;
          })}
          <circle cx="570" cy="530" r="30" fill="black" />
          <path d="M299 530 A271 271 0 0 0 732 747" fill="none" stroke="black" strokeWidth="16" />
          <path d="M370 326 A274 274 0 0 1 770 326" fill="none" stroke="black" strokeWidth="16" />
          <path d="M80 610 Q150 602 214 614" fill="none" stroke="black" strokeWidth="16" strokeLinecap="round" />
        </mask>
      </defs>
      <g fill={color} mask="url(#cut)">
        <path d="M150 820 Q120 820 124 792 Q130 760 190 752 L820 742 Q900 740 960 790 Q975 806 950 812 L870 822 Z" />
        <path d="M168 790 Q150 700 140 650 Q112 640 108 612 Q108 588 140 576 Q150 520 170 470 Q190 410 250 400 Q320 396 336 470 Q348 560 340 760 Z" />
        <ellipse cx="138" cy="584" rx="64" ry="34" />
        <ellipse cx="150" cy="636" rx="58" ry="32" />
        <path d="M222 420 Q200 340 168 270" fill="none" stroke={color} strokeWidth="34" strokeLinecap="round" />
        <ellipse cx="160" cy="248" rx="46" ry={46 * eye} />
        <path d="M280 412 Q282 330 270 262" fill="none" stroke={color} strokeWidth="30" strokeLinecap="round" />
        <ellipse cx="268" cy="238" rx="40" ry={40 * eye} />
        <circle cx="570" cy="530" r="262" />
        <path d="M420 246 Q570 158 720 246" fill="none" stroke={color} strokeWidth="44" strokeLinecap="round" />
        <ellipse cx="398" cy="276" rx="64" ry="34" transform="rotate(22 398 276)" />
        <ellipse cx="742" cy="276" rx="64" ry="34" transform="rotate(-22 742 276)" />
        <path
          d="M796.0 298.0 L793.9 330.9 L838.8 339.5 L817.9 380.3 L862.0 393.0 L838.1 432.4 L881.3 449.2 L854.6 487.4 L896.6 508.1 L867.3 545.1 L907.9 569.7 L876.3 605.6 L915.2 634.0 L881.4 669.0 L918.6 701.0 L882.8 735.2 L900.0 770.0"
          fill="none"
          stroke={color}
          strokeWidth="13"
          strokeLinejoin="round"
          strokeLinecap="round"
          pathLength={1}
          strokeDasharray={1}
          strokeDashoffset={1 - cord}
        />
      </g>
    </svg>
  );
};

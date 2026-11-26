import { useEffect, useRef, useState } from "react";
import { BOARD_SIZE, type BoardPoint, type BoardStroke, type BoardViewport } from "../services/lesson";

export type Tool = "pen" | "line" | "triangle" | "circle" | "rectangle" | "eraser";
export const TOOLS: Tool[] = ["pen", "line", "triangle", "circle", "rectangle", "eraser"];

// AppTheme's dark session colours.
const PANEL = "rgb(32, 31, 47)";
const DOT = "rgb(43, 42, 60)";
const PEN_TEACHER = "rgb(96, 165, 250)";
const PEN_STUDENT = "rgb(255, 255, 255)";
const PEER_VIEW = "rgba(84, 232, 246, 0.55)";
/** How close, in screen pixels, the eraser must pass (WhiteboardView.eraserRadius). */
const ERASER_RADIUS = 14;

/** The points a shape travels as (WhiteboardView.shapePoints). */
function shapePoints(a: BoardPoint, b: BoardPoint, tool: Tool): BoardPoint[] {
  switch (tool) {
    case "rectangle":
      return [a, { x: b.x, y: a.y }, b, { x: a.x, y: b.y }, a];
    case "triangle": {
      const midX = (a.x + b.x) / 2;
      return [{ x: midX, y: a.y }, b, { x: a.x, y: b.y }, { x: midX, y: a.y }];
    }
    case "circle": {
      const cx = (a.x + b.x) / 2, cy = (a.y + b.y) / 2;
      const rx = Math.abs(b.x - a.x) / 2, ry = Math.abs(b.y - a.y) / 2;
      return Array.from({ length: 49 }, (_, i) => {
        const t = (i * 2 * Math.PI) / 48;
        return { x: cx + rx * Math.cos(t), y: cy + ry * Math.sin(t) };
      });
    }
    default:
      return [a, b];
  }
}

function distanceToSegment(p: BoardPoint, a: BoardPoint, b: BoardPoint): number {
  const dx = b.x - a.x, dy = b.y - a.y;
  const len = dx * dx + dy * dy;
  const t = len ? Math.max(0, Math.min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len)) : 0;
  return Math.hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy));
}

function passesNear(points: BoardPoint[], p: BoardPoint, radius: number): boolean {
  if (points.length === 1) return Math.hypot(points[0].x - p.x, points[0].y - p.y) <= radius;
  for (let i = 1; i < points.length; i++) if (distanceToSegment(p, points[i - 1], points[i]) <= radius) return true;
  return false;
}

interface Props {
  strokes: BoardStroke[];
  uid: string;
  tool: Tool;
  teacherViewport: BoardViewport | null;
  canDraw: boolean;
  /** The teacher's side: their own ink is blue, and they may erase anything. */
  isTeacher?: boolean;
  /** A stroke was started without leave to draw. */
  onBlocked: () => void;
  onStroke: (points: BoardPoint[]) => void;
  onErase: (ids: string[]) => void;
}

/** The lesson's shared board. The whole board is in view, as on the iPad;
 *  the teacher's own view, when it is smaller, is outlined. */
export function Board({ strokes, uid, tool, teacherViewport, canDraw, isTeacher = false, onBlocked, onStroke, onErase }: Props) {
  // A stroke is coloured by who drew it, the same on both sides (BoardAuthor).
  const mine = isTeacher ? PEN_TEACHER : PEN_STUDENT;
  const theirs = isTeacher ? PEN_STUDENT : PEN_TEACHER;
  const box = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const [size, setSize] = useState({ w: 0, h: 0 });
  const active = useRef<BoardPoint[] | null>(null);
  const erased = useRef(new Set<string>());
  const [, redraw] = useState(0);

  useEffect(() => {
    const node = box.current;
    if (!node) return;
    const observer = new ResizeObserver(([entry]) => {
      setSize({ w: entry.contentRect.width, h: entry.contentRect.height });
    });
    observer.observe(node);
    return () => observer.disconnect();
  }, []);

  // What is shown: the board, widened to take in the teacher's view.
  const minX = Math.min(0, teacherViewport?.x ?? 0);
  const minY = Math.min(0, teacherViewport?.y ?? 0);
  const maxX = Math.max(BOARD_SIZE, teacherViewport ? teacherViewport.x + teacherViewport.width : 0);
  const maxY = Math.max(BOARD_SIZE, teacherViewport ? teacherViewport.y + teacherViewport.height : 0);
  const scale = size.w && size.h ? Math.min(size.w / (maxX - minX), size.h / (maxY - minY)) : 1;
  const offX = (size.w - (maxX - minX) * scale) / 2 - minX * scale;
  const offY = (size.h - (maxY - minY) * scale) / 2 - minY * scale;
  const toView = (p: BoardPoint) => ({ x: offX + p.x * scale, y: offY + p.y * scale });

  useEffect(() => {
    const c = canvas.current;
    if (!c || !size.w) return;
    const dpr = window.devicePixelRatio || 1;
    c.width = size.w * dpr;
    c.height = size.h * dpr;
    const g = c.getContext("2d")!;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    // The margins round the board take the panel colour too, so the board
    // reads as one surface, as on the iPad.
    g.fillStyle = PANEL;
    g.fillRect(0, 0, size.w, size.h);

    // The board itself, with the app's dot grid.
    const tl = toView({ x: 0, y: 0 });
    const side = BOARD_SIZE * scale;
    g.fillStyle = DOT;
    const step = 50 * scale;
    for (let x = tl.x + step; x < tl.x + side; x += step)
      for (let y = tl.y + step; y < tl.y + side; y += step) g.fillRect(x - 1, y - 1, 2, 2);

    if (teacherViewport && (teacherViewport.width < BOARD_SIZE || teacherViewport.height < BOARD_SIZE)) {
      const a = toView(teacherViewport);
      g.strokeStyle = PEER_VIEW;
      g.lineWidth = 2;
      g.setLineDash([6, 6]);
      g.strokeRect(a.x, a.y, teacherViewport.width * scale, teacherViewport.height * scale);
      g.setLineDash([]);
    }

    g.lineCap = "round";
    g.lineJoin = "round";
    g.lineWidth = 3;
    const path = (points: BoardPoint[], colour: string) => {
      g.strokeStyle = colour;
      g.fillStyle = colour;
      const first = toView(points[0]);
      if (points.length === 1) {
        g.beginPath();
        g.arc(first.x, first.y, 1.5, 0, Math.PI * 2);
        g.fill();
        return;
      }
      g.beginPath();
      g.moveTo(first.x, first.y);
      for (const p of points.slice(1)) {
        const v = toView(p);
        g.lineTo(v.x, v.y);
      }
      g.stroke();
    };
    for (const s of strokes) {
      if (!erased.current.has(s.id)) path(s.points, s.senderUid === uid ? mine : theirs);
    }
    const live = active.current;
    if (live?.length) {
      path(tool === "pen" ? live : shapePoints(live[0], live[live.length - 1], tool), mine);
    }
  });

  const logical = (e: React.PointerEvent): BoardPoint => {
    const r = canvas.current!.getBoundingClientRect();
    const x = (e.clientX - r.left - offX) / scale;
    const y = (e.clientY - r.top - offY) / scale;
    return { x: Math.round(Math.max(minX, Math.min(maxX, x))), y: Math.round(Math.max(minY, Math.min(maxY, y))) };
  };

  const eraseAt = (p: BoardPoint) => {
    const hits = strokes
      .filter((s) => (isTeacher || s.senderUid === uid) && !erased.current.has(s.id) && passesNear(s.points, p, ERASER_RADIUS / scale))
      .map((s) => s.id);
    if (!hits.length) return;
    hits.forEach((id) => erased.current.add(id));
    onErase(hits);
  };

  return (
    <div className="board" ref={box}>
      <canvas
        ref={canvas}
        style={{ width: size.w, height: size.h }}
        onPointerDown={(e) => {
          if (e.button !== 0) return;
          if (!canDraw) {
            onBlocked();
            return;
          }
          e.currentTarget.setPointerCapture(e.pointerId);
          const p = logical(e);
          if (tool === "eraser") {
            active.current = [];
            eraseAt(p);
          } else {
            active.current = [p];
          }
          redraw((n) => n + 1);
        }}
        onPointerMove={(e) => {
          if (!active.current) return;
          const p = logical(e);
          if (tool === "eraser") return eraseAt(p);
          if (tool === "pen") active.current.push(p);
          else active.current = [active.current[0], p];
          redraw((n) => n + 1);
        }}
        onPointerUp={() => {
          const points = active.current;
          active.current = null;
          if (points?.length && tool !== "eraser") {
            onStroke(tool === "pen" ? points : shapePoints(points[0], points[points.length - 1], tool));
          }
          redraw((n) => n + 1);
        }}
        onPointerCancel={() => {
          active.current = null;
          redraw((n) => n + 1);
        }}
      />
    </div>
  );
}

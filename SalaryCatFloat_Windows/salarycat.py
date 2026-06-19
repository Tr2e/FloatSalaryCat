#!/usr/bin/env python3
"""
月薪喵 (Salary Cat) — Windows Desktop Companion
A floating salary cat companion for your desktop.
Ported from the macOS Swift original.
"""

import sys
import os
from pathlib import Path

from PySide6.QtCore import (
    Qt, QPoint, QRect, QUrl,
)
from PySide6.QtGui import (
    QGuiApplication, QContextMenuEvent,
    QMouseEvent, QAction, QMovie, QPalette, QColor,
)
from PySide6.QtWidgets import (
    QApplication, QWidget, QLabel, QMenu,
    QSlider, QDialog, QDialogButtonBox,
    QVBoxLayout, QHBoxLayout, QMessageBox,
)
from PySide6.QtMultimedia import QMediaPlayer, QAudioOutput

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR = Path(__file__).resolve().parent
RESOURCES = SCRIPT_DIR / "Resources"
GIF_PATH = str(RESOURCES / "cat.GIF")
MUSIC_PATH = str(RESOURCES / "music.mp3")

BASE_IMAGE_SIZE = 240       # original GIF pixel size
REFERENCE_SIZE = 120        # default display size at scale 1.0 (Swift uses 0.5× = 120px)
DEFAULT_SCALE = 1.0         # start at 120×120
SIZE_MIN = 0.25
SIZE_MAX = 4.0
PAD_X = 20
PAD_Y = 40


# ---------------------------------------------------------------------------
# CatWindow — frameless, always-on-top, transparent GIF window
# ---------------------------------------------------------------------------

class CatWindow(QWidget):
    """Borderless transparent window that displays the animated cat GIF."""

    def __init__(self, gif_path: str):
        super().__init__()
        self._drag_start: QPoint | None = None
        self._window_start: QPoint | None = None
        self._corner_index = 0  # cycles counter‑clockwise: BR → TR → TL → BL
        self._current_scale = DEFAULT_SCALE
        self._context_menu: QMenu | None = None

        # --- Window flags & attributes ---------------------------------
        self.setWindowFlags(
            Qt.FramelessWindowHint
            | Qt.WindowStaysOnTopHint
            | Qt.Tool
            | Qt.NoDropShadowWindowHint
        )
        self.setAttribute(Qt.WA_TranslucentBackground)
        self.setAttribute(Qt.WA_ShowWithoutActivating)
        self._make_background_transparent()

        # --- GIF via QMovie on a QLabel --------------------------------
        self._movie = QMovie(gif_path)
        self._movie.setCacheMode(QMovie.CacheAll)

        self._label = QLabel(self)
        self._label.setMovie(self._movie)
        self._label.setAlignment(Qt.AlignCenter)
        self._label.setScaledContents(True)
        self._movie.start()

        # --- Initial size & position -----------------------------------
        size = int(REFERENCE_SIZE * self._current_scale)
        self.setFixedSize(size, size)
        self._label.setFixedSize(size, size)
        self._position_initial()

    # --- helpers -------------------------------------------------------

    def _make_background_transparent(self):
        pal = self.palette()
        pal.setColor(QPalette.Window, QColor(0, 0, 0, 0))
        self.setPalette(pal)
        self.setAutoFillBackground(True)

    def _all_screens_union(self) -> QRect:
        """Union of availableGeometry of every screen (matches NSScreen.visibleFrame union)."""
        screens = QGuiApplication.screens()
        if not screens:
            return QRect()
        union = screens[0].availableGeometry()
        for s in screens[1:]:
            union = union.united(s.availableGeometry())
        return union

    def _clamp_to_screens(self, pos: QPoint) -> QPoint:
        """Keep at least 30 px of the window visible on any screen edge."""
        union = self._all_screens_union()
        w, h = self.width(), self.height()
        x = max(union.left() - w + 30, min(pos.x(), union.right() - 30))
        y = max(union.top() - h + 30, min(pos.y(), union.bottom() - 30))
        return QPoint(x, y)

    def _position_initial(self):
        scr = QGuiApplication.primaryScreen()
        geo = scr.availableGeometry()
        x = geo.right() - self.width() - 30
        y = geo.top() + 60
        self.move(x, y)

    # --- corner cycling (counter‑clockwise: BR → TR → TL → BL → BR) ---

    def move_to_corner(self):
        union = self._all_screens_union()
        w, h = self.width(), self.height()

        origins = [
            QPoint(union.right() - w - PAD_X, union.top() + PAD_Y),               # Bottom-Right
            QPoint(union.right() - w - PAD_X, union.bottom() - h - PAD_Y),         # Top-Right
            QPoint(union.left() + PAD_X, union.bottom() - h - PAD_Y),              # Top-Left
            QPoint(union.left() + PAD_X, union.top() + PAD_Y),                     # Bottom-Left
        ]
        self.move(origins[self._corner_index])
        self._corner_index = (self._corner_index + 1) % 4

    # --- resize --------------------------------------------------------

    def resize_to_scale(self, scale: float):
        """Resize window to reference size × scale, keeping centre point."""
        self._movie.setPaused(True)
        size = int(REFERENCE_SIZE * scale)
        old_geo = self.geometry()
        center = old_geo.center()

        new_geo = QRect(0, 0, size, size)
        new_geo.moveCenter(center)
        new_pos = self._clamp_to_screens(new_geo.topLeft())

        self.setFixedSize(size, size)
        self._label.setFixedSize(size, size)
        self.move(new_pos)

        self._current_scale = scale
        self._movie.setPaused(False)

    # --- context menu (right‑click on the cat) --------------------------

    def set_context_menu(self, menu: QMenu):
        self._context_menu = menu

    def contextMenuEvent(self, event: QContextMenuEvent):
        if self._context_menu:
            self._context_menu.popup(event.globalPos())

    # --- drag via mouse events (replicates DraggableView) --------------

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() == Qt.LeftButton:
            self._drag_start = event.globalPosition().toPoint()
            self._window_start = self.pos()

    def mouseMoveEvent(self, event: QMouseEvent):
        if self._drag_start is not None and self._window_start is not None:
            delta = event.globalPosition().toPoint() - self._drag_start
            new_pos = self._window_start + delta
            new_pos = self._clamp_to_screens(new_pos)
            self.move(new_pos)

    def mouseReleaseEvent(self, event: QMouseEvent):
        if event.button() == Qt.LeftButton:
            self._drag_start = None
            self._window_start = None


# ---------------------------------------------------------------------------
# App — context menu, music, wiring
# ---------------------------------------------------------------------------

class App:
    """Top‑level application: right‑click menu on cat + music player."""

    def __init__(self):
        self._cat = CatWindow(GIF_PATH)
        self._cat.show()

        self._setup_menu()
        self._setup_audio()
        self._music_playing = False

    # --- context menu (right‑click on the cat) --------------------------

    def _setup_menu(self):
        menu = QMenu()

        # Music toggle
        self._music_action = QAction("🎵 Play Music")
        self._music_action.triggered.connect(self._toggle_music)
        menu.addAction(self._music_action)

        menu.addSeparator()

        # Corner switch
        self._corner_action = QAction("📍 Switch Corner")
        self._corner_action.triggered.connect(self._cat.move_to_corner)
        menu.addAction(self._corner_action)

        menu.addSeparator()

        # Size dialog
        self._size_action = QAction("Size...")
        self._size_action.triggered.connect(self._show_size_dialog)
        menu.addAction(self._size_action)

        menu.addSeparator()

        # About
        self._about_action = QAction("About 月薪喵")
        self._about_action.triggered.connect(self._show_about)
        menu.addAction(self._about_action)

        menu.addSeparator()

        self._quit_action = QAction("Quit")
        self._quit_action.triggered.connect(self._quit)
        menu.addAction(self._quit_action)

        self._cat.set_context_menu(menu)

    # --- music ---------------------------------------------------------

    def _setup_audio(self):
        self._player = QMediaPlayer()
        self._audio_output = QAudioOutput()
        self._player.setAudioOutput(self._audio_output)
        self._player.setSource(QUrl.fromLocalFile(MUSIC_PATH))
        self._player.setLoops(QMediaPlayer.Infinite)
        self._audio_output.setVolume(0.5)

    def _toggle_music(self):
        if self._music_playing:
            self._player.pause()
            self._music_playing = False
            self._music_action.setText("🎵 Play Music")
        else:
            self._player.play()
            self._music_playing = True
            self._music_action.setText("⏸ Pause Music")

    # --- size dialog ---------------------------------------------------

    def _show_size_dialog(self):
        dialog = QDialog()
        dialog.setWindowTitle("Adjust Cat Size")
        dialog.setFixedSize(280, 100)

        layout = QVBoxLayout(dialog)
        layout.setSpacing(10)

        # Slider + label row
        slider_row = QHBoxLayout()
        slider_row.setSpacing(8)

        slider = QSlider(Qt.Horizontal)
        slider.setRange(int(SIZE_MIN * 100), int(SIZE_MAX * 100))
        slider.setValue(int(self._cat._current_scale * 100))
        slider.setSingleStep(25)
        slider.setPageStep(100)
        slider.setFixedWidth(180)

        scale_label = QLabel(f"{self._cat._current_scale:.1f}×")
        scale_label.setFixedWidth(40)
        scale_label.setAlignment(Qt.AlignRight | Qt.AlignVCenter)

        slider.valueChanged.connect(
            lambda raw: self._on_size_slider(raw, slider, scale_label)
        )

        slider_row.addWidget(slider)
        slider_row.addWidget(scale_label)
        layout.addLayout(slider_row)

        # OK button
        buttons = QDialogButtonBox(QDialogButtonBox.Ok)
        buttons.accepted.connect(dialog.accept)
        layout.addWidget(buttons)

        dialog.exec()

    def _on_size_slider(self, raw: int, slider: QSlider, label: QLabel):
        val = raw / 100.0
        snapped = round(val * 4) / 4
        if snapped != val:
            slider.blockSignals(True)
            slider.setValue(int(snapped * 100))
            slider.blockSignals(False)
            val = snapped
        label.setText(f"{val:.1f}×")
        self._cat.resize_to_scale(val)

    # --- about ---------------------------------------------------------

    def _show_about(self):
        QMessageBox.about(
            None,
            "🐱 月薪喵 Desktop Companion",
            "A floating salary cat companion for your desktop.\n\n"
            "• Drag to move anywhere on screen\n"
            "• Right-click the cat for controls\n"
            "• Move to Corner cycles counterclockwise\n\n"
            "祝月薪翻倍！💰"
        )

    # --- quit ----------------------------------------------------------

    def _quit(self):
        self._player.stop()
        QApplication.quit()


# ---------------------------------------------------------------------------
# Main entry
# ---------------------------------------------------------------------------

def main():
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)

    companion = App()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

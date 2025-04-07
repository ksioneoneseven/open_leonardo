#!/bin/bash

# create.sh - Sets up the PyQt Paint Clone project structure (v2 - with fixes).

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
APP_DIR="paint_app"
PYTHON_CMD="python3" # Use python3 explicitly
VENV_DIR="venv_paint" # Recommended name for the virtual environment directory

# --- Start Script ---
echo "-------------------------------------------"
echo "Setting up PyQt Paint Clone project (v2)..."
echo "-------------------------------------------"

# --- Project Directory ---
echo "[1/6] Creating project directory: $APP_DIR/"
mkdir -p "$APP_DIR"

# --- Python Files ---

echo "[2/6] Creating file: $APP_DIR/__init__.py"
touch "$APP_DIR/__init__.py" # Create empty __init__.py

# --- canvas_widget.py (Corrected) ---
echo "[3/6] Creating file: $APP_DIR/canvas_widget.py"
# (Using 'heredoc' to embed the file content)
cat << 'EOF' > "$APP_DIR/canvas_widget.py"
import logging
# Corrected Import: Added QSizePolicy
from PyQt6.QtWidgets import QWidget, QSizePolicy
from PyQt6.QtGui import QPixmap, QPainter, QColor, QPen, QResizeEvent, QPaintEvent, QMouseEvent
from PyQt6.QtCore import Qt, QPoint, QSize

# --- Constants ---
DEFAULT_CANVAS_WIDTH = 600
DEFAULT_CANVAS_HEIGHT = 400
DEFAULT_BG_COLOR = QColor(Qt.GlobalColor.white)
DEFAULT_PEN_COLOR = QColor(Qt.GlobalColor.black)
DEFAULT_PEN_WIDTH = 2
MIN_PEN_WIDTH = 1
MAX_PEN_WIDTH = 100

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

class CanvasWidget(QWidget):
    """
    A custom QWidget for drawing. Uses a QPixmap as the drawing surface.
    Handles mouse events for drawing, resizing, clearing, and saving the canvas.
    """
    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        self._canvas = QPixmap(QSize(DEFAULT_CANVAS_WIDTH, DEFAULT_CANVAS_HEIGHT))
        self._canvas.fill(DEFAULT_BG_COLOR)
        self._drawing: bool = False
        self._last_point: QPoint = QPoint()
        self._pen_color: QColor = QColor(DEFAULT_PEN_COLOR)
        self._pen_width: int = DEFAULT_PEN_WIDTH

        self.setFocusPolicy(Qt.FocusPolicy.StrongFocus)
        # Corrected Line: Used imported QSizePolicy
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)
        self.setMinimumSize(DEFAULT_CANVAS_WIDTH // 2, DEFAULT_CANVAS_HEIGHT // 2)

        logging.info(f"CanvasWidget initialized. Initial Pixmap size: {self._canvas.size()}")

    def sizeHint(self) -> QSize:
        return self._canvas.size()

    def resizeEvent(self, event: QResizeEvent):
        new_size = event.size()
        old_size = self._canvas.size()
        if new_size != old_size and new_size.width() > 0 and new_size.height() > 0:
            logging.info(f"CanvasWidget resizeEvent. Old: {old_size}, New: {new_size}")
            new_canvas = QPixmap(new_size)
            new_canvas.fill(DEFAULT_BG_COLOR)
            painter = QPainter(new_canvas)
            painter.drawPixmap(0, 0, self._canvas)
            painter.end()
            self._canvas = new_canvas
            logging.info(f"Pixmap resized to: {self._canvas.size()}")
        super().resizeEvent(event)
        self.update()

    def paintEvent(self, event: QPaintEvent):
        painter = QPainter(self)
        painter.drawPixmap(0, 0, self._canvas)

    def mousePressEvent(self, event: QMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton:
            self._drawing = True
            self._last_point = event.position().toPoint()
        else:
            super().mousePressEvent(event)

    def mouseMoveEvent(self, event: QMouseEvent):
        if self._drawing and (event.buttons() & Qt.MouseButton.LeftButton):
            current_point = event.position().toPoint()
            painter = QPainter(self._canvas)
            pen = QPen(self._pen_color, self._pen_width,
                       Qt.PenStyle.SolidLine, Qt.PenCapStyle.RoundCap, Qt.PenJoinStyle.RoundJoin)
            painter.setPen(pen)
            painter.drawLine(self._last_point, current_point)
            painter.end()
            self._last_point = current_point
            self.update()
        else:
            super().mouseMoveEvent(event)

    def mouseReleaseEvent(self, event: QMouseEvent):
        if event.button() == Qt.MouseButton.LeftButton and self._drawing:
            self._drawing = False
        else:
            super().mouseReleaseEvent(event)

    def set_pen_color(self, color: QColor):
        if isinstance(color, QColor) and color.isValid():
            self._pen_color = color
            logging.info(f"Pen color set to: {color.name()}")
        else:
            logging.warning(f"Invalid color received for pen: {color}")

    def set_pen_width(self, width: int):
        if isinstance(width, int):
            clamped_width = max(MIN_PEN_WIDTH, min(width, MAX_PEN_WIDTH))
            if clamped_width != self._pen_width:
                self._pen_width = clamped_width
                logging.info(f"Pen width set to: {self._pen_width}")
            elif width != clamped_width:
                 logging.warning(f"Requested pen width {width} outside range [{MIN_PEN_WIDTH}-{MAX_PEN_WIDTH}]. Clamped to {clamped_width}.")
        else:
            logging.warning(f"Invalid width type received for pen: {type(width)}. Ignored.")

    def clear_canvas(self):
        logging.info("Clearing canvas...")
        self._canvas.fill(DEFAULT_BG_COLOR)
        self.update()

    def get_canvas_pixmap(self) -> QPixmap:
         return self._canvas

    def save_canvas(self, file_path: str) -> bool:
        if not file_path:
            logging.error("Save canvas failed: No file path provided.")
            return False
        pixmap_to_save = self.get_canvas_pixmap()
        try:
            success = pixmap_to_save.save(file_path, format=None)
            if not success:
                logging.error(f"Save canvas failed: QPixmap.save() returned False for path {file_path}")
                return False
            else:
                logging.info(f"Canvas successfully saved to {file_path}")
                return True
        except Exception as e:
            logging.error(f"Save canvas failed: Exception occurred while saving to {file_path}. Error: {e}", exc_info=True)
            return False

__all__ = [
    'CanvasWidget', 'DEFAULT_PEN_WIDTH', 'DEFAULT_PEN_COLOR', 'DEFAULT_BG_COLOR',
    'MIN_PEN_WIDTH', 'MAX_PEN_WIDTH'
]
EOF

# --- main_window.py ---
echo "[4/6] Creating file: $APP_DIR/main_window.py"
cat << 'EOF' > "$APP_DIR/main_window.py"
import os
import logging
from PyQt6.QtWidgets import (QMainWindow, QToolBar, QMenu, QWidget, QLabel,
                             QColorDialog, QSpinBox, QFileDialog, QMessageBox,
                             QStatusBar)
from PyQt6.QtGui import QAction, QIcon, QPixmap, QPainter, QColor, QCloseEvent
from PyQt6.QtCore import QSize, Qt, QStandardPaths, QDir

from .canvas_widget import (CanvasWidget, DEFAULT_PEN_WIDTH, DEFAULT_PEN_COLOR,
                            MIN_PEN_WIDTH, MAX_PEN_WIDTH)

DEFAULT_WINDOW_TITLE = "PyQt Paint Clone"
DEFAULT_SAVE_FILENAME = "untitled.png"
SUPPORTED_IMAGE_FORMATS = "PNG Files (*.png);;JPEG Files (*.jpg *.jpeg);;Bitmap Files (*.bmp);;All Files (*)"

class MainWindow(QMainWindow):
    """
    Main application window class. Sets up UI and connects actions.
    """
    def __init__(self, parent: QWidget | None = None):
        super().__init__(parent)
        self.setWindowTitle(DEFAULT_WINDOW_TITLE)
        self.canvas = CanvasWidget()
        self.setCentralWidget(self.canvas)
        menu_bar = self.menuBar()
        self._create_file_menu(menu_bar)
        self._create_edit_menu(menu_bar)
        self.toolbar = QToolBar("Main Toolbar")
        self.toolbar.setIconSize(QSize(24, 24))
        self.toolbar.setAllowedAreas(Qt.ToolBarArea.TopToolBarArea | Qt.ToolBarArea.BottomToolBarArea)
        self.addToolBar(Qt.ToolBarArea.TopToolBarArea, self.toolbar)
        self._populate_toolbar()
        self.status_bar = QStatusBar(self)
        self.setStatusBar(self.status_bar)
        self.status_bar.showMessage("Ready", 3000)
        self.adjustSize()

    def _create_file_menu(self, menu_bar: QMenu):
        file_menu = menu_bar.addMenu("&File")
        self.save_action = QAction(QIcon.fromTheme("document-save", QIcon("icons/save.png")), "&Save", self)
        self.save_action.setShortcut("Ctrl+S")
        self.save_action.setStatusTip("Save the current drawing to a file")
        self.save_action.triggered.connect(self._save_canvas_triggered)
        file_menu.addAction(self.save_action)
        file_menu.addSeparator()
        exit_action = QAction(QIcon.fromTheme("application-exit", QIcon("icons/exit.png")), "&Exit", self)
        exit_action.setShortcut("Ctrl+Q")
        exit_action.setStatusTip("Exit the application")
        exit_action.triggered.connect(self.close)
        file_menu.addAction(exit_action)

    def _create_edit_menu(self, menu_bar: QMenu):
        edit_menu = menu_bar.addMenu("&Edit")
        self.clear_action = QAction(QIcon.fromTheme("edit-clear", QIcon("icons/clear.png")), "&Clear Canvas", self)
        self.clear_action.setShortcut("Ctrl+N")
        self.clear_action.setStatusTip("Clear the entire drawing canvas")
        self.clear_action.triggered.connect(self._clear_canvas_triggered)
        edit_menu.addAction(self.clear_action)

    def _populate_toolbar(self):
        self.color_action = QAction(self._create_color_icon(DEFAULT_PEN_COLOR), "Pen &Color...", self)
        self.color_action.setStatusTip("Select Pen Color")
        self.color_action.triggered.connect(self._select_pen_color)
        self.toolbar.addAction(self.color_action)
        self.toolbar.addSeparator()
        size_label = QLabel(" Brush Size: ")
        self.toolbar.addWidget(size_label)
        self.pen_size_spinbox = QSpinBox()
        self.pen_size_spinbox.setRange(MIN_PEN_WIDTH, MAX_PEN_WIDTH)
        self.pen_size_spinbox.setSuffix(" px")
        self.pen_size_spinbox.setValue(DEFAULT_PEN_WIDTH)
        self.pen_size_spinbox.setStatusTip(f"Select Pen Width ({MIN_PEN_WIDTH}-{MAX_PEN_WIDTH} pixels)")
        self.pen_size_spinbox.setFocusPolicy(Qt.FocusPolicy.ClickFocus)
        self.pen_size_spinbox.valueChanged.connect(self._change_pen_width)
        self.toolbar.addWidget(self.pen_size_spinbox)
        self.toolbar.addSeparator()
        self.toolbar.addAction(self.save_action)
        self.toolbar.addAction(self.clear_action)

    def _create_color_icon(self, color: QColor) -> QIcon:
        pixmap = QPixmap(16, 16)
        pixmap.fill(Qt.GlobalColor.transparent)
        painter = QPainter(pixmap)
        painter.setBrush(color)
        painter.setPen(QColor(Qt.GlobalColor.gray))
        painter.drawRect(0, 0, 15, 15)
        painter.end()
        return QIcon(pixmap)

    def _select_pen_color(self):
        initial_color = self.canvas._pen_color
        selected_color = QColorDialog.getColor(initial_color, self, "Select Pen Color")
        if selected_color.isValid():
            self.canvas.set_pen_color(selected_color)
            self.color_action.setIcon(self._create_color_icon(selected_color))
            self.status_bar.showMessage(f"Pen color changed to {selected_color.name()}", 3000)

    def _change_pen_width(self, value: int):
        self.canvas.set_pen_width(value)
        self.status_bar.showMessage(f"Pen width set to {value} px", 3000)

    def _clear_canvas_triggered(self):
        self.canvas.clear_canvas()
        self.status_bar.showMessage("Canvas Cleared", 3000)

    def _save_canvas_triggered(self):
        default_dir = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.PicturesLocation)
        if not default_dir:
            default_dir = QStandardPaths.writableLocation(QStandardPaths.StandardLocation.HomeLocation)
        default_save_path = os.path.join(default_dir, DEFAULT_SAVE_FILENAME)
        file_path, selected_filter = QFileDialog.getSaveFileName(
            parent=self, caption="Save Drawing As", directory=default_save_path, filter=SUPPORTED_IMAGE_FORMATS)
        if not file_path:
            self.status_bar.showMessage("Save cancelled", 3000)
            return
        try:
            success = self.canvas.save_canvas(file_path)
            if success:
                self.status_bar.showMessage(f"Saved to {QDir.toNativeSeparators(file_path)}", 5000)
            else:
                QMessageBox.warning(self, "Save Error", f"Failed to save the image to\n{file_path}")
                self.status_bar.showMessage("Save failed", 3000)
        except Exception as e:
            logging.error(f"An unexpected error occurred during save trigger: {e}", exc_info=True)
            QMessageBox.critical(self, "Save Error", f"An unexpected error occurred while trying to save:\n{e}")
            self.status_bar.showMessage("Save error occurred", 3000)

    def closeEvent(self, event: QCloseEvent):
        logging.info("Close event triggered.")
        event.accept()
EOF

# --- main.py ---
echo "[5/6] Creating file: $APP_DIR/main.py"
cat << 'EOF' > "$APP_DIR/main.py"
import sys
import logging
from PyQt6.QtWidgets import QApplication

from .main_window import MainWindow

APP_NAME = "PyQt Paint Clone"
APP_VERSION = "0.2"
ORGANIZATION_NAME = "MyPaintApp"
ORGANIZATION_DOMAIN = "mypaintapp.org"

def run_app():
    """Initializes and runs the PyQt application."""
    logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
    logging.info(f"Starting {APP_NAME} v{APP_VERSION}")

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setApplicationVersion(APP_VERSION)
    app.setOrganizationName(ORGANIZATION_NAME)
    app.setOrganizationDomain(ORGANIZATION_DOMAIN)

    main_window = MainWindow()
    main_window.show()
    logging.info("Main window shown.")

    logging.info("Starting application event loop...")
    exit_code = app.exec()
    logging.info(f"Application event loop finished. Exit code: {exit_code}")
    sys.exit(exit_code)

if __name__ == "__main__":
    run_app()
EOF

# --- Optional: Icons Directory ---
echo "[6/6] Creating optional directory: $APP_DIR/icons/"
mkdir -p "$APP_DIR/icons"

# --- Final Instructions ---
echo ""
echo "-------------------------------------------"
echo " Project setup complete!"
echo "-------------------------------------------"
echo ""
echo " NEXT STEPS:"
echo ""
echo " 1. Install required system libraries for Qt:"
echo "    (This is needed for the GUI to display correctly on X11/XCB systems like Ubuntu/Pop!_OS)"
echo "    $ sudo apt update"
echo "    $ sudo apt install libxcb-cursor0"
echo ""
echo " 2. Create a Python virtual environment (recommended):"
echo "    $ $PYTHON_CMD -m venv $VENV_DIR"
echo ""
echo " 3. Activate the virtual environment:"
echo "    $ source $VENV_DIR/bin/activate"
echo "    (Your terminal prompt should change to indicate activation)"
echo ""
echo " 4. Install the required Python dependency (PyQt6):"
echo "    (Make sure the venv is active before running pip)"
echo "    $ pip install PyQt6"
echo ""
echo " 5. Run the application:"
echo "    (Make sure the venv is still active and you are in the directory *containing* '$APP_DIR')"
echo "    $ python -m $APP_DIR.main"
echo ""
echo " 6. (Optional) Place fallback icon files (e.g., save.png) in the '$APP_DIR/icons/' directory."
echo ""
echo "-------------------------------------------"

exit 0

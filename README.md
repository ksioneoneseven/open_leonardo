# open_leonardo
A paint application created using vibe coding

# PyQt Paint Clone

A simple drawing application built with Python and PyQt6, mimicking basic Microsoft Paint functionality.

## Features

* Draw on a canvas using a brush tool (mouse).
* Select brush color using a color picker dialog.
* Adjust brush size using a spin box.
* Clear the entire canvas.
* Save the drawing as a PNG, JPEG, or BMP file.
* Basic menu bar and toolbar for actions.

## Requirements

* **Operating System:** Tested on Ubuntu 22.04 / Pop!_OS 22.04 (Should work on other Linux distributions with X11 or Wayland). Windows/macOS might require different system dependency steps.
* **Python:** Version 3.10 or higher.
* **System Libraries (for Linux/X11):**
    * `libxcb-cursor0` (Install via `sudo apt install libxcb-cursor0` on Debian/Ubuntu-based systems). Qt needs this for proper display server integration.
* **Python Packages:**
    * `PyQt6`

## Setup and Installation

Follow these steps to set up and run the application:

1.  **Get the Code:**
    * If you have the `create.sh` script, run it in your desired project directory:
        ```bash
        ./create.sh
        ```
    * Alternatively, if you cloned or downloaded the source code, ensure you have the `paint_app` directory containing the Python files.

2.  **Install System Dependencies (Linux - Debian/Ubuntu/Pop!_OS):**
    * Open a terminal and run:
        ```bash
        sudo apt update
        sudo apt install libxcb-cursor0
        ```
    * *(Note: If you are on a different OS or using Wayland primarily, this specific library might not be needed, but PyQt might have other system requirements.)*

3.  **Create Python Virtual Environment:**
    * Navigate to the directory containing the `paint_app` folder (e.g., `paint_clone`).
    * Create a virtual environment (named `venv_paint` here, but you can choose another name):
        ```bash
        python3 -m venv venv_paint
        ```

4.  **Activate Virtual Environment:**
    * Activate the created environment:
        ```bash
        source venv_paint/bin/activate
        ```
    * Your terminal prompt should now indicate that the environment is active (e.g., `(venv_paint) user@host:...$`).

5.  **Install Python Packages:**
    * With the virtual environment active, install PyQt6:
        ```bash
        pip install PyQt6
        ```

## Running the Application

1.  **Ensure Virtual Environment is Active:** If you closed your terminal, reactivate the environment:
    ```bash
    source venv_paint/bin/activate
    ```
2.  **Navigate to the Project Directory:** Make sure you are in the directory that *contains* the `paint_app` folder (e.g., `paint_clone`).
3.  **Run as a Module:** Execute the following command:
    ```bash
    python -m paint_app.main
    ```
    The application window should appear.

## Project Structure

paint_clone/
├── paint_app/
│   ├── init.py         # Makes paint_app a Python package
│   ├── canvas_widget.py    # Custom widget for the drawing canvas
│   ├── main_window.py      # Defines the main application window, menus, toolbar
│   └── main.py             # Main application entry point script
├── venv_paint/             # Python virtual environment (if created)
├── create.sh               # (Optional) Script to generate the project
└── README.md               # This file

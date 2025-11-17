use std::collections::HashSet;
use std::fs;
use std::io::{self, stdout};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Duration;

use crossterm::{
    event::{self, Event, KeyCode, KeyEvent, KeyEventKind},
    execute,
    terminal::{EnterAlternateScreen, LeaveAlternateScreen, disable_raw_mode, enable_raw_mode},
};
use ratatui::{
    Terminal,
    prelude::*,
    text::{Line, Span},
    widgets::{Block, Borders, List, ListItem, ListState, Paragraph, Wrap},
};
use reqwest::blocking::Client;
use which::which;

const BREWFILE_SOURCE_ENV: &str = "BREWFILE_SOURCE";
const BREWFILE_PATH_ENV: &str = "BREWFILE_PATH";
const BREWFILE_URL_ENV: &str = "BREWFILE_URL";
const DEFAULT_BREWFILE_URL: &str = "https://raw.githubusercontent.com/isaaclins/dotfiles/HEAD/Brewfile";

fn main() {
    if let Err(err) = run() {
        eprintln!("Error: {err}");
        std::process::exit(1);
    }
}

fn run() -> io::Result<()> {
    let mut app = App::new().map_err(|err| io::Error::new(io::ErrorKind::Other, err))?;

    enable_raw_mode()?;
    let mut stdout = stdout();
    execute!(stdout, EnterAlternateScreen)?;
    let backend = ratatui::prelude::CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let result = run_app(&mut terminal, &mut app);

    disable_raw_mode()?;
    execute!(terminal.backend_mut(), LeaveAlternateScreen)?;
    terminal.show_cursor()?;

    result
}

fn run_app<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> io::Result<()> {
    loop {
        terminal.draw(|frame| draw(frame, app))?;
        if app.should_quit {
            break;
        }

        if event::poll(Duration::from_millis(150))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }
                match app.handle_key(key) {
                    Action::None => {}
                    Action::StartInstall => {
                        perform_installations(terminal, app)?;
                    }
                }
            }
        }
    }
    Ok(())
}

#[derive(Clone, Debug)]
struct Tool {
    kind: ToolKind,
    name: String,
    label: String,
    description: String,
    fallbacks: Vec<String>,
    app_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
enum ToolKind {
    BrewFormula,
    BrewCask,
    Mas,
}

#[derive(Clone, Debug)]
struct ToolState {
    tool: Tool,
    selected: bool,
    status: Option<Status>,
}

#[derive(Clone, Debug)]
enum Status {
    Pending(String),
    Success(String),
    Skipped(String),
    Failed(String),
}

impl Status {
    fn message(&self) -> &str {
        match self {
            Status::Pending(msg)
            | Status::Success(msg)
            | Status::Skipped(msg)
            | Status::Failed(msg) => msg,
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Mode {
    Selecting,
    Confirm,
    Results,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Action {
    None,
    StartInstall,
}

struct Symbols {
    success: &'static str,
    failure: &'static str,
    pending: &'static str,
}

impl Symbols {
    fn new() -> Self {
        if std::env::var("NO_EMOJI").ok().as_deref() == Some("1") {
            Symbols {
                success: "[OK]",
                failure: "[X]",
                pending: "[...]",
            }
        } else {
            Symbols {
                success: "[✅]",
                failure: "[❌]",
                pending: "[…]",
            }
        }
    }
}

struct App {
    items: Vec<ToolState>,
    index: usize,
    mode: Mode,
    info: Option<String>,
    progress: Option<String>,
    should_quit: bool,
    symbols: Symbols,
}

impl App {
    fn new() -> Result<Self, String> {
        let (items, info) = load_tools_from_brewfile()?;
        Ok(Self {
            items,
            index: 0,
            mode: Mode::Selecting,
            info,
            progress: None,
            should_quit: false,
            symbols: Symbols::new(),
        })
    }

    fn handle_key(&mut self, key: KeyEvent) -> Action {
        match self.mode {
            Mode::Selecting => self.handle_selecting(key),
            Mode::Confirm => self.handle_confirm(key),
            Mode::Results => self.handle_results(key),
        }
    }

    fn handle_selecting(&mut self, key: KeyEvent) -> Action {
        match key.code {
            KeyCode::Char('q') | KeyCode::Esc => {
                self.should_quit = true;
            }
            KeyCode::Up | KeyCode::Char('k') => {
                self.info = None;
                if self.index > 0 {
                    self.index -= 1;
                }
            }
            KeyCode::Down | KeyCode::Char('j') => {
                self.info = None;
                if self.index + 1 < self.items.len() {
                    self.index += 1;
                }
            }
            KeyCode::Char(' ') => {
                if let Some(item) = self.items.get_mut(self.index) {
                    item.selected = !item.selected;
                    self.info = None;
                }
            }
            KeyCode::Char('a') | KeyCode::Char('A') => {
                for item in &mut self.items {
                    item.selected = true;
                }
                self.info = Some("All tools selected.".to_string());
            }
            KeyCode::Char('d') | KeyCode::Char('D') => {
                for item in &mut self.items {
                    item.selected = false;
                }
                self.info = Some("Selections cleared.".to_string());
            }
            KeyCode::Enter => {
                if self.selected_count() == 0 {
                    self.info = Some("Select at least one tool before continuing.".to_string());
                } else {
                    self.mode = Mode::Confirm;
                    self.info = None;
                }
            }
            _ => {}
        }
        Action::None
    }

    fn handle_confirm(&mut self, key: KeyEvent) -> Action {
        match key.code {
            KeyCode::Char('y') | KeyCode::Char('Y') => {
                self.mode = Mode::Results;
                self.progress = Some("Preparing installations...".to_string());
                Action::StartInstall
            }
            KeyCode::Char('n') | KeyCode::Char('N') | KeyCode::Esc => {
                self.mode = Mode::Selecting;
                self.progress = None;
                Action::None
            }
            KeyCode::Char('q') => {
                self.should_quit = true;
                Action::None
            }
            _ => Action::None,
        }
    }

    fn handle_results(&mut self, key: KeyEvent) -> Action {
        match key.code {
            KeyCode::Enter | KeyCode::Char('q') | KeyCode::Esc => {
                self.should_quit = true;
            }
            _ => {}
        }
        Action::None
    }

    fn selected_count(&self) -> usize {
        self.items.iter().filter(|item| item.selected).count()
    }

    fn selected_indices(&self) -> Vec<usize> {
        self.items
            .iter()
            .enumerate()
            .filter_map(|(idx, item)| if item.selected { Some(idx) } else { None })
            .collect()
    }

    fn clear_statuses(&mut self) {
        for item in &mut self.items {
            item.status = None;
        }
    }

    fn set_status(&mut self, idx: usize, status: Status) {
        if let Some(item) = self.items.get_mut(idx) {
            item.status = Some(status);
        }
    }

    fn current_description(&self) -> Option<&str> {
        self.items
            .get(self.index)
            .map(|item| item.tool.description.as_str())
    }

    fn selected_labels(&self) -> Vec<String> {
        self.items
            .iter()
            .filter(|item| item.selected)
            .map(|item| item.tool.label.clone())
            .collect()
    }
}

fn load_tools_from_brewfile() -> Result<(Vec<ToolState>, Option<String>), String> {
    let (contents, note) = load_brewfile_text()?;
    let items = parse_brewfile(&contents);
    if items.is_empty() {
        Err("Brewfile did not contain any brew/cask/mas entries".to_string())
    } else {
        Ok((items, note))
    }
}

fn load_brewfile_text() -> Result<(String, Option<String>), String> {
    if let Ok(source) = std::env::var(BREWFILE_SOURCE_ENV) {
        let trimmed = source.trim();
        if trimmed.is_empty() {
            return Err(format!("{BREWFILE_SOURCE_ENV} was set but empty"));
        }
        let text = load_spec(trimmed)?;
        return Ok((text, Some(format!("Loaded Brewfile from {trimmed}"))));
    }

    if let Ok(path) = std::env::var(BREWFILE_PATH_ENV) {
        let trimmed = path.trim();
        if trimmed.is_empty() {
            return Err(format!("{BREWFILE_PATH_ENV} was set but empty"));
        }
        let text = load_from_path(trimmed)?;
        return Ok((text, Some(format!("Loaded Brewfile from {trimmed}"))));
    }

    if let Ok(url) = std::env::var(BREWFILE_URL_ENV) {
        let trimmed = url.trim();
        if trimmed.is_empty() {
            return Err(format!("{BREWFILE_URL_ENV} was set but empty"));
        }
        let text = fetch_brewfile(trimmed)?;
        return Ok((text, Some(format!("Loaded Brewfile from {trimmed}"))));
    }

    if let Some(path) = find_local_brewfile()? {
        let display = path.display().to_string();
        let text = fs::read_to_string(&path)
            .map_err(|err| format!("Failed to read Brewfile at {display}: {err}"))?;
        return Ok((text, Some(format!("Loaded Brewfile from {display}"))));
    }

    let text = fetch_brewfile(DEFAULT_BREWFILE_URL)?;
    Ok((
        text,
        Some(format!(
            "Loaded Brewfile from {DEFAULT_BREWFILE_URL}. Override with {BREWFILE_SOURCE_ENV}, {BREWFILE_PATH_ENV}, or {BREWFILE_URL_ENV}."
        )),
    ))
}

fn load_spec(spec: &str) -> Result<String, String> {
    if looks_like_url(spec) {
        fetch_brewfile(spec)
    } else {
        load_from_path(spec)
    }
}

fn load_from_path(spec: &str) -> Result<String, String> {
    let path = expand_home(spec);
    let display = path.display().to_string();
    fs::read_to_string(&path)
        .map_err(|err| format!("Failed to read Brewfile at {display}: {err}"))
}

fn fetch_brewfile(url: &str) -> Result<String, String> {
    let client = Client::builder()
        .timeout(Duration::from_secs(10))
        .user_agent("install-tools-tui")
        .build()
        .map_err(|err| format!("Failed to build HTTP client: {err}"))?;

    let response = client
        .get(url)
        .send()
        .map_err(|err| format!("Failed to fetch Brewfile from {url}: {err}"))?;

    if !response.status().is_success() {
        return Err(format!(
            "Request to {url} returned status {}",
            response.status()
        ));
    }

    response
        .text()
        .map_err(|err| format!("Failed to read Brewfile contents: {err}"))
}

fn looks_like_url(spec: &str) -> bool {
    let lower = spec.to_ascii_lowercase();
    lower.starts_with("http://") || lower.starts_with("https://")
}

fn expand_home(spec: &str) -> PathBuf {
    if let Some(rest) = spec.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return Path::new(&home).join(rest);
        }
    } else if spec == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home);
        }
    }
    PathBuf::from(spec)
}

fn find_local_brewfile() -> Result<Option<PathBuf>, String> {
    let mut dir = std::env::current_dir()
        .map_err(|err| format!("Failed to determine current directory: {err}"))?;
    loop {
        let candidate = dir.join("Brewfile");
        if candidate.is_file() {
            return Ok(Some(candidate));
        }
        if !dir.pop() {
            break;
        }
    }
    Ok(None)
}

fn parse_brewfile(contents: &str) -> Vec<ToolState> {
    let mut tools = Vec::new();
    let mut seen = HashSet::new();
    let mut pending_comment: Option<String> = None;

    for line in contents.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            pending_comment = None;
            continue;
        }

        if let Some(comment) = trimmed.strip_prefix('#') {
            let text = comment.trim();
            if text.is_empty() {
                continue;
            }
            match &mut pending_comment {
                Some(existing) => {
                    existing.push(' ');
                    existing.push_str(text);
                }
                None => pending_comment = Some(text.to_string()),
            }
            continue;
        }

        if let Some(name) = extract_first_quoted(trimmed) {
            if trimmed.starts_with("brew ") {
                let key = (ToolKind::BrewFormula, name.clone());
                if seen.insert(key) {
                    let description = pending_comment
                        .take()
                        .unwrap_or_else(|| format!("Homebrew formula '{name}'"));
                    tools.push(ToolState {
                        tool: Tool {
                            kind: ToolKind::BrewFormula,
                            name: name.clone(),
                            label: format!("{name} (brew formula)"),
                            description,
                            fallbacks: Vec::new(),
                            app_id: None,
                        },
                        selected: false,
                        status: None,
                    });
                } else {
                    pending_comment = None;
                }
                continue;
            }

            if trimmed.starts_with("cask ") {
                let key = (ToolKind::BrewCask, name.clone());
                if seen.insert(key) {
                    let description = pending_comment
                        .take()
                        .unwrap_or_else(|| format!("Homebrew cask '{name}'"));
                    tools.push(ToolState {
                        tool: Tool {
                            kind: ToolKind::BrewCask,
                            name: name.clone(),
                            label: format!("{name} (cask)"),
                            description,
                            fallbacks: Vec::new(),
                            app_id: None,
                        },
                        selected: false,
                        status: None,
                    });
                } else {
                    pending_comment = None;
                }
                continue;
            }

            if trimmed.starts_with("mas ") {
                if let Some(raw_id) = trimmed.split("id:").nth(1) {
                    let app_id: String = raw_id.chars().filter(|ch| ch.is_ascii_digit()).collect();
                    if !app_id.is_empty() {
                        let key = (ToolKind::Mas, app_id.clone());
                        if seen.insert(key) {
                            let label = name.clone();
                            let description = pending_comment.take().unwrap_or_else(|| {
                                format!("Mac App Store app '{label}' (id {app_id})")
                            });
                            tools.push(ToolState {
                                tool: Tool {
                                    kind: ToolKind::Mas,
                                    name: label.clone(),
                                    label: format!("{label} (App Store)"),
                                    description,
                                    fallbacks: Vec::new(),
                                    app_id: Some(app_id.clone()),
                                },
                                selected: false,
                                status: None,
                            });
                        }
                    }
                }
                pending_comment = None;
                continue;
            }
        }

        pending_comment = None;
    }

    tools
}

fn extract_first_quoted(line: &str) -> Option<String> {
    let start = line.find('"')? + 1;
    let rest = &line[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn draw(frame: &mut Frame, app: &App) {
    match app.mode {
        Mode::Selecting => draw_selection(frame, app),
        Mode::Confirm => draw_confirm(frame, app),
        Mode::Results => draw_results(frame, app),
    }
}

fn draw_selection(frame: &mut Frame, app: &App) {
    let area = frame.size();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(
            [
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(2),
                Constraint::Length(3),
            ]
            .as_ref(),
        )
        .split(area);

    let title = Paragraph::new("Select what tools you want:")
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().add_modifier(Modifier::BOLD));
    frame.render_widget(title, chunks[0]);

    let items: Vec<ListItem> = app
        .items
        .iter()
        .map(|item| {
            let marker = if item.selected { "[x]" } else { "[ ]" };
            ListItem::new(format!("{marker} {}", item.tool.label))
        })
        .collect();
    let list = List::new(items)
        .block(Block::default().borders(Borders::ALL))
        .highlight_style(Style::default().add_modifier(Modifier::REVERSED));
    let mut state = ListState::default();
    state.select(Some(app.index));
    frame.render_stateful_widget(list, chunks[1], &mut state);

    let instructions = Paragraph::new(
        "[space - Toggle Selection] [a - Select All] [d - Deselect All] [enter - Install Selected Tools] [q - Quit]",
    )
    .wrap(Wrap { trim: true })
    .style(Style::default().fg(Color::Gray));
    frame.render_widget(instructions, chunks[2]);

    let mut lines = Vec::new();
    if let Some(info) = &app.info {
        lines.push(Line::styled(
            info.clone(),
            Style::default().fg(Color::Yellow),
        ));
    }
    if let Some(desc) = app.current_description() {
        lines.push(Line::styled(
            desc.to_string(),
            Style::default().fg(Color::Gray),
        ));
    }
    if lines.is_empty() {
        lines.push(Line::raw(""));
    }
    let footer = Paragraph::new(lines)
        .block(Block::default().borders(Borders::NONE))
        .wrap(Wrap { trim: true });
    frame.render_widget(footer, chunks[3]);
}

fn draw_confirm(frame: &mut Frame, app: &App) {
    let area = frame.size();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(
            [
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(2),
            ]
            .as_ref(),
        )
        .split(area);

    let title_text = format!("Install {} tool(s)? (y/n)", app.selected_count());
    let title = Paragraph::new(title_text)
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().add_modifier(Modifier::BOLD));
    frame.render_widget(title, chunks[0]);

    let selected = app.selected_labels();
    let list_lines: Vec<Line> = selected
        .into_iter()
        .map(|label| Line::raw(format!("- {label}")))
        .collect();
    let list_block = Paragraph::new(list_lines)
        .block(Block::default().borders(Borders::ALL))
        .wrap(Wrap { trim: true });
    frame.render_widget(list_block, chunks[1]);

    let instruction = Paragraph::new("Press y to confirm, n to go back, q to quit.")
        .style(Style::default().fg(Color::Gray));
    frame.render_widget(instruction, chunks[2]);
}

fn draw_results(frame: &mut Frame, app: &App) {
    let area = frame.size();
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .margin(1)
        .constraints(
            [
                Constraint::Length(3),
                Constraint::Min(5),
                Constraint::Length(2),
            ]
            .as_ref(),
        )
        .split(area);

    let title = Paragraph::new("Select what tools you want:")
        .block(Block::default().borders(Borders::NONE))
        .alignment(Alignment::Center)
        .style(Style::default().add_modifier(Modifier::BOLD));
    frame.render_widget(title, chunks[0]);

    let items: Vec<ListItem> = app
        .items
        .iter()
        .map(|item| {
            let marker = if !item.selected {
                "[ ]".to_string()
            } else if let Some(status) = &item.status {
                status_marker(status, &app.symbols).to_string()
            } else {
                "[x]".to_string()
            };

            let mut lines = Vec::new();
            let mut spans = Vec::new();
            spans.push(Span::raw(format!("{marker} {}", item.tool.label)));
            if let Some(status) = &item.status {
                let style = status_style(status);
                spans.push(Span::raw(" "));
                spans.push(Span::styled(status_label(status), style));
            }
            lines.push(Line::from(spans));

            if let Some(status) = &item.status {
                let message = status.message();
                if !message.is_empty() {
                    lines.push(Line::styled(
                        format!("    - {message}"),
                        Style::default().fg(Color::Gray),
                    ));
                }
            }

            ListItem::new(lines)
        })
        .collect();

    let list = List::new(items).block(Block::default().borders(Borders::ALL));
    frame.render_widget(list, chunks[1]);

    let footer_text = app
        .progress
        .clone()
        .unwrap_or_else(|| "Press Enter or q to exit.".to_string());
    let footer = Paragraph::new(footer_text).style(Style::default().fg(Color::Gray));
    frame.render_widget(footer, chunks[2]);
}

fn status_marker(status: &Status, symbols: &Symbols) -> &'static str {
    match status {
        Status::Pending(_) => symbols.pending,
        Status::Success(_) | Status::Skipped(_) => symbols.success,
        Status::Failed(_) => symbols.failure,
    }
}

fn status_style(status: &Status) -> Style {
    match status {
        Status::Pending(_) => Style::default().fg(Color::Yellow),
        Status::Success(_) => Style::default().fg(Color::Green),
        Status::Skipped(_) => Style::default().fg(Color::Green),
        Status::Failed(_) => Style::default().fg(Color::Red),
    }
}

fn status_label(status: &Status) -> &'static str {
    match status {
        Status::Pending(_) => "pending",
        Status::Success(_) => "installed",
        Status::Skipped(_) => "skipped",
        Status::Failed(_) => "failed",
    }
}

fn perform_installations<B: Backend>(terminal: &mut Terminal<B>, app: &mut App) -> io::Result<()> {
    app.clear_statuses();
    let indices = app.selected_indices();
    let total = indices.len();
    for (position, &idx) in indices.iter().enumerate() {
        let label = app.items[idx].tool.label.clone();
        app.set_status(idx, Status::Pending("Installing...".to_string()));
        app.progress = Some(format!("Installing {}/{}: {label}", position + 1, total));
        terminal.draw(|frame| draw(frame, app))?;

        let result = install_tool(&app.items[idx].tool);
        app.set_status(idx, result);
        app.progress = Some(format!("Completed {}/{}: {label}", position + 1, total));
        terminal.draw(|frame| draw(frame, app))?;
    }

    app.progress = Some("Installation complete. Press Enter or q to exit.".to_string());
    terminal.draw(|frame| draw(frame, app))?;
    Ok(())
}

fn install_tool(tool: &Tool) -> Status {
    match tool.kind {
        ToolKind::BrewFormula => install_brew_formula(&tool.name),
        ToolKind::BrewCask => install_brew_cask(&tool.name, &tool.fallbacks),
        ToolKind::Mas => {
            if let Some(app_id) = &tool.app_id {
                install_mas_app(app_id, &tool.name)
            } else {
                Status::Failed("Missing MAS app id".to_string())
            }
        }
    }
}

fn install_brew_formula(name: &str) -> Status {
    if !brew_available() {
        return Status::Failed("Homebrew not available".to_string());
    }

    if brew_list_installed("--formula", name) {
        return Status::Skipped("Already installed".to_string());
    }

    match run_command(&["brew", "install", name]) {
        Ok(output) if output.status.success() => Status::Success(
            shorten_message(&output.stdout).unwrap_or_else(|| "Installed".to_string()),
        ),
        Ok(output) => Status::Failed(
            shorten_message(&output.stderr)
                .or_else(|| shorten_message(&output.stdout))
                .unwrap_or_else(|| format!("Exit status {}", output.status_code())),
        ),
        Err(err) => Status::Failed(format!("Failed to run brew: {err}")),
    }
}

fn install_brew_cask(name: &str, fallbacks: &[String]) -> Status {
    if !brew_available() {
        return Status::Failed("Homebrew not available".to_string());
    }

    let mut candidates = Vec::new();
    candidates.push(name.to_string());
    candidates.extend(fallbacks.iter().cloned());

    for candidate in &candidates {
        if brew_list_installed("--cask", candidate) {
            let suffix = if candidate != name {
                " (via fallback)"
            } else {
                ""
            };
            return Status::Skipped(format!("Already installed{suffix}"));
        }
    }

    let mut last_error = None;
    for candidate in &candidates {
        match run_command(&["brew", "install", "--cask", candidate]) {
            Ok(output) if output.status.success() => {
                let mut message =
                    shorten_message(&output.stdout).unwrap_or_else(|| "Installed".to_string());
                if candidate != name {
                    message.push_str(" (fallback)");
                }
                return Status::Success(message);
            }
            Ok(output) => {
                last_error = Some(
                    shorten_message(&output.stderr)
                        .or_else(|| shorten_message(&output.stdout))
                        .unwrap_or_else(|| format!("Exit status {}", output.status_code())),
                );
            }
            Err(err) => {
                last_error = Some(format!("Failed to run brew: {err}"));
            }
        }
    }

    Status::Failed(last_error.unwrap_or_else(|| "Install failed".to_string()))
}

fn install_mas_app(app_id: &str, label: &str) -> Status {
    if !mas_available() {
        return Status::Failed("mas CLI not available".to_string());
    }

    match run_command(&["mas", "list"]) {
        Ok(output) if output.status.success() => {
            if output
                .stdout
                .lines()
                .any(|line| line.trim_start().starts_with(app_id))
            {
                return Status::Skipped("Already installed".to_string());
            }
        }
        Ok(_) => {} // ignore non-zero result, attempt install anyway
        Err(err) => {
            return Status::Failed(format!("Failed to run mas list: {err}"));
        }
    }

    match run_command(&["mas", "install", app_id]) {
        Ok(output) if output.status.success() => Status::Success(
            shorten_message(&output.stdout).unwrap_or_else(|| format!("Installed {label}")),
        ),
        Ok(output) => Status::Failed(
            shorten_message(&output.stderr)
                .or_else(|| shorten_message(&output.stdout))
                .unwrap_or_else(|| format!("Exit status {}", output.status_code())),
        ),
        Err(err) => Status::Failed(format!("Failed to run mas install: {err}")),
    }
}

fn brew_available() -> bool {
    which("brew").is_ok()
}

fn mas_available() -> bool {
    which("mas").is_ok()
}

fn brew_list_installed(flag: &str, name: &str) -> bool {
    match run_command(&["brew", "list", flag, "--versions", name]) {
        Ok(output) => output.status.success(),
        Err(_) => false,
    }
}

struct CommandOutput {
    status: std::process::ExitStatus,
    stdout: String,
    stderr: String,
}

impl CommandOutput {
    fn status_code(&self) -> i32 {
        self.status.code().unwrap_or(-1)
    }
}

fn run_command(args: &[&str]) -> io::Result<CommandOutput> {
    let mut command = Command::new(args[0]);
    if args.len() > 1 {
        command.args(&args[1..]);
    }
    command.stdout(std::process::Stdio::piped());
    command.stderr(std::process::Stdio::piped());
    let output = command.output()?;
    Ok(CommandOutput {
        status: output.status,
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

fn shorten_message(output: &str) -> Option<String> {
    let line = output.lines().next()?.trim();
    if line.is_empty() {
        return None;
    }
    const MAX_LEN: usize = 80;
    if line.len() <= MAX_LEN {
        Some(line.to_string())
    } else {
        let mut shortened = line[..MAX_LEN.min(line.len())].trim_end().to_string();
        shortened.push('…');
        Some(shortened)
    }
}

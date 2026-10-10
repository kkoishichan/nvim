//! Event store sample with deliberate diagnostics (rust-analyzer + clippy).
//!
//! Intended findings:
//!   - unused imports and unused variables (warnings)
//!   - dead code: never-used functions and struct fields (warnings)
//!   - E0308 mismatched types
//!   - E0382 use of moved value
//!   - E0004 non-exhaustive match
//!   - E0599 no method named ... found
//!   - unused `Result` that must be used (warning)
//!   - clippy: needless_return, len_zero, redundant_clone, manual range contains

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;
use std::io::Write;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct StreamId(pub u32);

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EventKind {
    Created,
    Updated { field: String },
    Deleted,
    Archived,
}

#[derive(Debug, Clone)]
pub struct Event {
    pub stream: StreamId,
    pub sequence: u64,
    pub kind: EventKind,
    pub payload: Vec<u8>,
    pub recorded_at: Instant,
}

#[derive(Debug)]
pub enum StoreError {
    UnknownStream(StreamId),
    SequenceConflict { expected: u64, found: u64 },
    PayloadTooLarge(usize),
    Closed,
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::UnknownStream(id) => write!(f, "unknown stream {}", id.0),
            StoreError::SequenceConflict { expected, found } => {
                write!(f, "expected sequence {expected}, found {found}")
            }
            StoreError::PayloadTooLarge(size) => write!(f, "payload of {size} bytes is too large"),
            StoreError::Closed => write!(f, "store is closed"),
        }
    }
}

impl std::error::Error for StoreError {}

pub type StoreResult<T> = Result<T, StoreError>;

#[derive(Debug, Default)]
pub struct Stream {
    events: Vec<Event>,
    archived: bool,
    label: String, // diag: field never read (dead_code)
}

impl Stream {
    pub fn len(&self) -> usize {
        self.events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    pub fn last_sequence(&self) -> u64 {
        self.events.last().map(|event| event.sequence).unwrap_or(0)
    }

    fn describe(&self) -> String {
        let count = self.events.len();
        let unused_total = count * 2; // diag: unused variable
        format!("{count} events, archived={}", self.archived)
    }
}

pub struct EventStore {
    streams: BTreeMap<StreamId, Stream>,
    max_payload: usize,
    closed: bool,
    subscribers: Vec<Box<dyn Fn(&Event) + Send>>,
}

impl EventStore {
    pub fn new(max_payload: usize) -> Self {
        Self {
            streams: BTreeMap::new(),
            max_payload,
            closed: false,
            subscribers: Vec::new(),
        }
    }

    pub fn create_stream(&mut self, id: StreamId) -> StoreResult<()> {
        if self.closed {
            return Err(StoreError::Closed);
        }
        self.streams.entry(id).or_default();
        Ok(())
    }

    pub fn subscribe<F>(&mut self, callback: F)
    where
        F: Fn(&Event) + Send + 'static,
    {
        self.subscribers.push(Box::new(callback));
    }

    pub fn append(&mut self, stream: StreamId, expected: u64, kind: EventKind, payload: Vec<u8>) -> StoreResult<u64> {
        if self.closed {
            return Err(StoreError::Closed);
        }
        if payload.len() > self.max_payload {
            return Err(StoreError::PayloadTooLarge(payload.len()));
        }
        let entry = self.streams.get_mut(&stream).ok_or(StoreError::UnknownStream(stream))?;
        let found = entry.last_sequence();
        if found != expected {
            return Err(StoreError::SequenceConflict { expected, found });
        }
        let event = Event {
            stream,
            sequence: found + 1,
            kind,
            payload,
            recorded_at: Instant::now(),
        };
        for subscriber in &self.subscribers {
            subscriber(&event);
        }
        entry.events.push(event);
        return Ok(found + 1); // diag: clippy needless_return
    }

    pub fn read(&self, stream: StreamId, from: u64) -> StoreResult<Vec<&Event>> {
        let entry = self.streams.get(&stream).ok_or(StoreError::UnknownStream(stream))?;
        Ok(entry.events.iter().filter(|event| event.sequence >= from).collect())
    }

    pub fn archive(&mut self, stream: StreamId) -> StoreResult<usize> {
        let entry = self.streams.get_mut(&stream).ok_or(StoreError::UnknownStream(stream))?;
        entry.archived = true;
        let archived: u32 = entry.events.len(); // diag: E0308 usize is not u32
        Ok(archived as usize)
    }

    pub fn summary(&self) -> String {
        let mut lines = Vec::new();
        for (id, stream) in &self.streams {
            lines.push(format!("{}: {}", id.0, stream.describe()));
        }
        lines.join("\n")
    }

    pub fn close(&mut self) {
        self.closed = true;
    }

    pub fn stream_count(&self) -> usize {
        self.streams.len()
    }
}

pub struct Projection {
    counts: HashMap<StreamId, u64>,
    deleted: HashSet<StreamId>,
    last_field: Option<String>,
}

impl Projection {
    pub fn new() -> Self {
        Self {
            counts: HashMap::new(),
            deleted: HashSet::new(),
            last_field: None,
        }
    }

    pub fn apply(&mut self, event: &Event) {
        *self.counts.entry(event.stream).or_insert(0) += 1;
        match &event.kind {
            EventKind::Created => {}
            EventKind::Updated { field } => self.last_field = Some(field.clone()),
            EventKind::Deleted => {
                self.deleted.insert(event.stream);
            }
        } // diag: E0004 non-exhaustive, Archived not covered
    }

    pub fn is_deleted(&self, stream: StreamId) -> bool {
        self.deleted.contains(&stream)
    }

    pub fn count(&self, stream: StreamId) -> u64 {
        self.counts.get(&stream).copied().unwrap_or(0)
    }

    pub fn busiest(&self) -> Option<StreamId> {
        self.counts.iter().max_by_key(|(_, count)| **count).map(|(id, _)| *id)
    }

    pub fn has_updates(&self) -> bool {
        if self.counts.len() > 0 { // diag: clippy len_zero
            self.last_field.is_some()
        } else {
            false
        }
    }
}

impl Default for Projection {
    fn default() -> Self {
        Self::new()
    }
}

pub fn replay(store: &EventStore, stream: StreamId) -> StoreResult<Projection> {
    let mut projection = Projection::new();
    for event in store.read(stream, 0)? {
        projection.apply(event);
    }
    Ok(projection)
}

pub fn snapshot(store: &EventStore, stream: StreamId) -> Vec<u8> {
    let name = format!("stream-{}", stream.0);
    let owned = name.clone(); // diag: clippy redundant_clone
    let mut buffer = Vec::with_capacity(64);
    buffer.extend_from_slice(owned.as_bytes());
    if let Ok(events) = store.read(stream, 0) {
        for event in events {
            buffer.extend_from_slice(&event.sequence.to_le_bytes());
        }
    }
    buffer
}

pub fn ingest(store: &mut EventStore, stream: StreamId, payloads: Vec<Vec<u8>>) -> StoreResult<u64> {
    let mut sequence = 0;
    for payload in payloads {
        let kind = if payload.is_empty() { EventKind::Deleted } else { EventKind::Created };
        sequence = store.append(stream, sequence, kind, payload)?;
    }
    Ok(sequence)
}

pub fn batch_sizes(total: usize, batch: usize) -> Vec<usize> {
    let mut sizes = Vec::new();
    let mut remaining = total;
    while remaining > 0 {
        let size = remaining.min(batch);
        sizes.push(size);
        remaining -= size;
    }
    sizes
}

pub fn is_recent(event: &Event, window: Duration) -> bool {
    let age = event.recorded_at.elapsed();
    age >= Duration::ZERO && age <= window // diag: clippy manual_range_contains
}

pub fn transfer(payload: Vec<u8>) -> (Vec<u8>, usize) {
    let moved = payload;
    let length = payload.len(); // diag: E0382 use of moved value
    (moved, length)
}

pub fn rename_stream(store: &mut EventStore, from: StreamId, to: StreamId) -> StoreResult<()> {
    let stream = store.streams.remove(&from).ok_or(StoreError::UnknownStream(from))?;
    store.streams.insert(to, stream);
    store.rebuild_index(); // diag: E0599 no method named rebuild_index
    Ok(())
}

pub fn demo() -> EventStore {
    let mut store = EventStore::new(1024);
    store.subscribe(|event| {
        let _ = event.sequence;
    });
    let orders = StreamId(1);
    let customers = StreamId(2);
    store.create_stream(orders).unwrap();
    store.create_stream(customers); // diag: unused Result must be used
    let _ = ingest(&mut store, orders, vec![b"created".to_vec(), b"paid".to_vec(), Vec::new()]);
    let _ = store.append(customers, 0, EventKind::Updated { field: "email".into() }, b"a@b.c".to_vec());
    let _ = store.archive(orders);
    store
}

fn unused_helper(values: &[u64]) -> u64 { // diag: function is never used (dead_code)
    values.iter().sum()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn appends_in_order() {
        let mut store = EventStore::new(16);
        store.create_stream(StreamId(7)).unwrap();
        assert_eq!(store.append(StreamId(7), 0, EventKind::Created, vec![]).unwrap(), 1);
        assert_eq!(store.append(StreamId(7), 1, EventKind::Deleted, vec![]).unwrap(), 2);
        assert!(matches!(
            store.append(StreamId(7), 0, EventKind::Deleted, vec![]),
            Err(StoreError::SequenceConflict { expected: 0, found: 2 })
        ));
    }

    #[test]
    fn batches_cover_total() {
        assert_eq!(batch_sizes(10, 4), vec![4, 4, 2]);
        assert!(batch_sizes(0, 4).is_empty());
    }
}

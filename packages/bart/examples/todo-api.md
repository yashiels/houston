# Feature: Todo API

## Overview

Build a simple REST API for managing todo items. The API should support full CRUD operations with proper validation and error handling.

## Requirements

- Create a new todo with title and optional description
- List all todos with optional filtering by status
- Get a single todo by ID
- Update a todo's title, description, or completion status
- Delete a todo
- Todos persist in memory (no database required for MVP)

## Acceptance Criteria

- POST /todos creates a new todo and returns it with a generated ID
- GET /todos returns an array of all todos
- GET /todos?completed=true filters by completion status
- GET /todos/:id returns a single todo or 404 if not found
- PUT /todos/:id updates a todo and returns the updated version
- DELETE /todos/:id removes a todo and returns 204
- Invalid requests return appropriate error codes (400, 404, 500)
- All endpoints return proper JSON with Content-Type header

## Technical Notes

- Use Node.js with Express
- Use TypeScript for type safety
- Use Vitest for unit testing
- Each todo should have: id (uuid), title, description, completed, createdAt, updatedAt
- Follow REST conventions for status codes
- Add input validation for required fields

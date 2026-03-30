package com.customer.service;

import com.customer.dto.CustomerNoteRequest;
import com.customer.dto.CustomerNoteResponse;
import com.customer.exception.CustomerNotFoundException;
import com.customer.exception.ResourceNotFoundException;
import com.customer.model.Customer;
import com.customer.model.CustomerNote;
import com.customer.repository.CustomerNoteRepository;
import com.customer.repository.CustomerRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@Transactional
public class CustomerNoteService {

    private final CustomerNoteRepository noteRepository;
    private final CustomerRepository customerRepository;

    public CustomerNoteService(CustomerNoteRepository noteRepository, CustomerRepository customerRepository) {
        this.noteRepository = noteRepository;
        this.customerRepository = customerRepository;
    }

    @Transactional(readOnly = true)
    public List<CustomerNoteResponse> getNotesByCustomerId(String customerId) {
        verifyCustomerExists(customerId);
        return noteRepository.findByCustomerCustomerId(customerId).stream()
                .map(this::toResponse)
                .toList();
    }

    @Transactional(readOnly = true)
    public CustomerNoteResponse getNoteById(String customerId, Long noteId) {
        verifyCustomerExists(customerId);
        CustomerNote note = noteRepository.findById(noteId)
                .orElseThrow(() -> new ResourceNotFoundException("Note with ID " + noteId + " not found"));
        if (!note.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Note with ID " + noteId + " not found for customer " + customerId);
        }
        return toResponse(note);
    }

    public CustomerNoteResponse createNote(String customerId, CustomerNoteRequest request) {
        Customer customer = customerRepository.findById(customerId)
                .orElseThrow(() -> new CustomerNotFoundException("Customer with ID " + customerId + " not found"));

        CustomerNote note = new CustomerNote();
        note.setNoteText(request.noteText());
        note.setCustomer(customer);

        CustomerNote saved = noteRepository.save(note);
        return toResponse(saved);
    }

    public void deleteNote(String customerId, Long noteId) {
        verifyCustomerExists(customerId);
        CustomerNote note = noteRepository.findById(noteId)
                .orElseThrow(() -> new ResourceNotFoundException("Note with ID " + noteId + " not found"));
        if (!note.getCustomer().getCustomerId().equals(customerId)) {
            throw new ResourceNotFoundException("Note with ID " + noteId + " not found for customer " + customerId);
        }
        noteRepository.delete(note);
    }

    private void verifyCustomerExists(String customerId) {
        if (!customerRepository.existsById(customerId)) {
            throw new CustomerNotFoundException("Customer with ID " + customerId + " not found");
        }
    }

    private CustomerNoteResponse toResponse(CustomerNote note) {
        return new CustomerNoteResponse(
                note.getId(),
                note.getCustomer().getCustomerId(),
                note.getNoteText(),
                note.getCreatedAt(),
                note.getUpdatedAt()
        );
    }
}

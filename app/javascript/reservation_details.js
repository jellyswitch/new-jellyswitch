$(document).ready(function () {
    $("#extend-button").off("click.extend").on("click.extend", function () {
        const reservationId = $(this).data("reservation-id");

        $.ajax({
            url: `/reservations/${reservationId}/available_extension_durations`,
            method: "GET",
            success: function (data) {
                const select = $("#extension-duration");
                const options = select.find("option");

                select.trigger("change.extend-duration");

                options.each(function () {
                    const option = $(this);
                    const duration = parseInt(option.val());

                    if (!data.includes(duration)) {
                        option.prop("disabled", true);
                    } else {
                        option.prop("disabled", false);
                    }
                });
            },
            error: function (xhr, status, error) {
                console.error("Error fetching available durations:", error);
            }
        });
    });

    $("#extension-duration").off("change.extend-duration").on("change.extend-duration", function () {
        const reservationId = $("#extend-button").data("reservation-id");
        const selectedDuration = parseInt($(this).val());

        $.ajax({
            url: `/reservations/${reservationId}/calculate_additional_hour_price`,
            method: "GET",
            data: { duration: selectedDuration },
            success: function ({ should_charge, additional_price, new_end_time }) {
                $("#additional-price").text(should_charge ? additional_price : "Free");
                $("#new-reservation-end-time").text(new_end_time);
            },
            error: function (xhr, status, error) {
                console.error("Error calculating additional price:", error);
            }
        });
    });

    $("#confirm-extension").off("click").on("click", function () {
        const reservationId = $("#extend-button").data("reservation-id");
        const selectedDuration = parseInt($("#extension-duration").val());

        $.ajax({
            url: `/reservations/${reservationId}/extend_reservation`,
            method: "PUT",
            data: { duration: selectedDuration },
            error: function (xhr, status, error) {
                console.error("Error extending reservation:", error);
            }
        });
    });
});